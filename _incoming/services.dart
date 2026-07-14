// lib/services/services.dart
//
// Transport + inference contracts. Pure abstractions — no platform imports —
// so implementations can be swapped per target:
//   iOS/Android : BLE + Wi-Fi Direct (e.g. nearby_connections / flutter_ble)
//   Web PWA     : WebRTC DataChannel over local network (BLE/Wi-Fi Direct
//                 are NOT available in browsers — see architecture note in
//                 the delivery message).

import 'dart:async';
import 'dart:typed_data';

import '../domain/domain_models.dart';

/// Connectivity lifecycle of a discovered mesh peer.
enum MeshNodeState { discovered, connecting, connected, degraded, lost }

/// Discovery event pairing an identity with its transport state.
class NodeDiscoveryEvent {
  const NodeDiscoveryEvent({
    required this.node,
    required this.state,
    required this.rssi,
  });

  final NodeIdentity node;
  final MeshNodeState state;

  /// Signal strength in dBm (BLE) or a normalized link-quality proxy
  /// (Wi-Fi Direct / WebRTC). Used by the routing layer to prefer paths.
  final int rssi;
}

/// Thrown when a broadcast cannot reach any connected peer. Callers must
/// treat this as a retriable condition — deltas stay durable in Isar and
/// are re-gossiped on the next connectivity window (store-and-forward).
class MeshUnreachableException implements Exception {
  const MeshUnreachableException(this.message);
  final String message;

  @override
  String toString() => 'MeshUnreachableException: $message';
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

abstract class LocalMeshTransportService {
  /// Hot broadcast stream of peer discovery / state transitions.
  /// Implementations must emit [MeshNodeState.lost] on timeout so the UI
  /// and router never hold stale peers.
  Stream<NodeDiscoveryEvent> get onNodeDiscovered;

  /// Inbound CRDT deltas from peers. Payloads arrive signature-UNVERIFIED;
  /// the CRDT engine verifies Ed25519 signatures before persistence.
  Stream<List<CrdtStateLog>> get onDeltaReceived;

  /// Begin advertising + scanning. Idempotent: calling while active is a
  /// no-op. Completes when the radio stack is live, not when peers exist.
  Future<void> startDiscovery({required NodeIdentity selfIdentity});

  /// Stop radios and release platform channels. Safe to call when inactive.
  Future<void> stopDiscovery();

  /// Gossip a batch of deltas to all currently connected peers.
  ///
  /// Contract:
  ///  - MUST chunk to transport MTU (BLE GATT ≈ 512 B per write) internally.
  ///  - MUST throw [MeshUnreachableException] if zero peers are connected,
  ///    so the caller keeps the batch queued rather than assuming delivery.
  ///  - MUST NOT mutate [elements].
  Future<void> broadcastDelta(List<CrdtStateLog> elements);

  /// Targeted unicast for ring-completion handshakes where flooding the
  /// mesh would leak intent metadata to uninvolved peers.
  Future<void> sendDeltaToPeer(
    String peerPublicKey,
    List<CrdtStateLog> elements,
  );

  /// Tear down streams and native resources. The instance is unusable after.
  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// Storage repository — backend-agnostic persistence contract
// ---------------------------------------------------------------------------
//
// Amendment 4: the domain layer depends only on this interface. Bindings:
//   iOS/Android : IsarMeshRepository (Isar 3.x, memory-mapped)
//   Web PWA     : DriftWasmMeshRepository or isar_community backend
// Swapping backends must never touch the CRDT engine or UI.

abstract class MeshRepository {
  // --- NodeIdentity ---

  /// Upsert keyed on cryptographicPublicKey. Returns the persisted row id.
  Future<int> upsertNodeIdentity(NodeIdentity node);

  Future<NodeIdentity?> findNodeByPublicKey(String publicKey);

  /// Reactive query for the dashboard peer list. Emits on every mutation.
  Stream<List<NodeIdentity>> watchAllNodes();

  // --- ResourceIntent ---

  /// Upsert keyed on intentUuid (replace semantics — CRDT-materialized
  /// state always wins over a stale local row).
  Future<int> upsertIntent(ResourceIntent intent);

  Future<ResourceIntent?> findIntentByUuid(String intentUuid);

  /// Full corpus scan for one category (optionally one direction) —
  /// feeds graph algorithms like ring matching that need every candidate,
  /// not a similarity-ranked subset.
  Future<List<ResourceIntent>> readIntentsByCategory(
    AllocationCategory category, {
    IntentDirection? direction,
  });

  /// Brute-force cosine scan over stored Float32 vectors, descending by
  /// similarity. Adequate for on-device corpus sizes (<50k rows); swap for
  /// an HNSW sidecar behind this same signature if the corpus outgrows it.
  Future<List<ResourceIntent>> semanticSearch(
    List<double> queryEmbedding, {
    int limit = 20,
    double minSimilarity = 0.35,
    AllocationCategory? category,
  });

  // --- CrdtStateLog ---

  /// Idempotent batch insert: rows whose transactionUuid already exists are
  /// skipped silently (gossip redelivery is the normal case, not an error).
  /// Returns the number of rows actually written.
  Future<int> appendDeltas(List<CrdtStateLog> deltas);

  /// All operations for one intent in [CrdtStateLog.causalCompare] order —
  /// served by the (targetIntentUuid, lamportLogicalClock) composite index.
  Future<List<CrdtStateLog>> readCausalLog(String targetIntentUuid);

  /// Deltas newer than [afterLamportClock], for gossip anti-entropy rounds.
  Future<List<CrdtStateLog>> readDeltasSince(int afterLamportClock);

  /// Highest Lamport clock seen locally; 0 for an empty log. Used to stamp
  /// the next local operation (`max + 1`).
  Future<int> currentLamportClock();

  /// Close the underlying backend (Isar instance / wasm connection).
  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// Delta applier — materialization hook for the sync engine
// ---------------------------------------------------------------------------

/// Applies newly persisted CRDT deltas onto materialized state (intent
/// rows). The engine invokes this AFTER durable append and BEFORE
/// notifying listeners, so UI recomputation always observes post-fold
/// rows. Implementations must be idempotent: re-applying the same deltas
/// must converge to the same state.
abstract class DeltaApplier {
  Future<void> applyDeltas(List<CrdtStateLog> deltas);
}

// ---------------------------------------------------------------------------
// Identity signer — local Ed25519 signing authority
// ---------------------------------------------------------------------------

/// Signs locally-authored CRDT operations with this device's Ed25519
/// private key. The key itself never crosses this interface: platform
/// implementations keep it in Keychain/Keystore (native) or IndexedDB
/// via WebCrypto non-extractable keys (web).
abstract class IdentitySigner {
  /// Hex-encoded public half — must equal the NodeIdentity this device
  /// advertises on the mesh.
  String get publicKeyHex;

  /// Ed25519 signature over [message], hex-encoded. For CrdtStateLog the
  /// canonical preimage is utf8(operationPayloadJson) || lamportClock as
  /// 8 little-endian bytes — matching CrdtStateLog.authoritySignature docs.
  Future<String> signToHex(Uint8List message);
}

// ---------------------------------------------------------------------------
// Inference
// ---------------------------------------------------------------------------

/// Backend actually selected by the implementation at runtime.
enum InferenceAccelerator { coreMlNpu, nnapi, gpuDelegate, cpuFallback }

abstract class EdgeInferenceService {
  /// Loads the embedding model onto the best available accelerator
  /// (CoreML/NPU on iOS, NNAPI on Android, WASM-SIMD on web). Must be
  /// awaited before [generateEmbedding]; safe to call repeatedly.
  Future<void> warmUp();

  /// The accelerator chosen during [warmUp], for telemetry surfaces.
  InferenceAccelerator get activeAccelerator;

  /// Embed [input] into a normalized vector of exactly
  /// [kEmbeddingDimensions] length.
  ///
  /// Contract:
  ///  - MUST L2-normalize the output (dot product == cosine similarity,
  ///    letting the matcher skip norm computation on the hot path).
  ///  - MUST throw [StateError] if called before [warmUp] completes.
  ///  - MUST truncate/window inputs beyond the model context internally
  ///    rather than throwing — user text length is not the caller's problem.
  Future<List<double>> generateEmbedding(String input);

  /// Release model memory / native handles.
  Future<void> dispose();
}
