// lib/engine/mesh_sync_engine.dart
//
// Reactive execution engine binding MeshRepository (storage) and
// LocalMeshTransportService (transport) into a single lifecycle, and
// projecting a UI-consumable state snapshot for DashboardView.
//
// Layering: this file imports domain + services only — never the UI.
// The UI-side adapter (MeshEngineState → DashboardState) lives next to
// dashboard_view.dart so the engine stays presentation-agnostic.
//
// Concurrency model: Dart single-isolate event loop. "Thread safety" of
// the exposed ValueNotifier is guaranteed by construction — all mutations
// happen on the main isolate; the only hazards are async interleavings,
// which are handled by the serialized sync queue and post-await guards.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../domain/domain_models.dart';
import '../services/services.dart';

/// Max deltas per transport frame during anti-entropy. Keeps individual
/// payloads bounded so the native layer's MTU chunking never has to split
/// a single JSON blob across an unreasonable number of GATT writes.
const int _kSyncBatchSize = 64;

// ---------------------------------------------------------------------------
// Engine state model
// ---------------------------------------------------------------------------

enum MeshConnectionState {
  /// Engine stopped, transport down, or terminal trust failure.
  disconnected,

  /// Discovery/handshake in progress; zero connected peers yet.
  connecting,

  /// At least one authenticated transport link is live
  /// (verified WebSocket bridge on web, connected peer on native).
  secureBridge,
}

enum MeshSyncStatus { idle, syncing, error }

/// Immutable snapshot of engine state. Every mutation produces a new
/// instance via [copyWith], so listeners can rely on value equality of
/// references for cheap change detection.
class MeshEngineState {
  const MeshEngineState({
    this.connectionState = MeshConnectionState.disconnected,
    this.verifiedPeers = const [],
    this.localClock = 0,
    this.syncStatus = MeshSyncStatus.idle,
    this.lastError,
  });

  final MeshConnectionState connectionState;

  /// Peers currently in [MeshNodeState.connected], keyed order stable by
  /// insertion. Degraded/lost peers are excluded — the router must never
  /// pick a path through a peer the transport can't reach.
  final List<NodeIdentity> verifiedPeers;

  /// Highest Lamport clock persisted locally. The CRDT engine stamps the
  /// next local operation with `localClock + 1`.
  final int localClock;

  final MeshSyncStatus syncStatus;

  /// Human-readable description of the most recent failure; null when
  /// [syncStatus] != error. Cleared on the next successful operation.
  final String? lastError;

  MeshEngineState copyWith({
    MeshConnectionState? connectionState,
    List<NodeIdentity>? verifiedPeers,
    int? localClock,
    MeshSyncStatus? syncStatus,
    String? lastError,
    bool clearError = false,
  }) =>
      MeshEngineState(
        connectionState: connectionState ?? this.connectionState,
        verifiedPeers: verifiedPeers ?? this.verifiedPeers,
        localClock: localClock ?? this.localClock,
        syncStatus: syncStatus ?? this.syncStatus,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class MeshSyncEngine {
  MeshSyncEngine({
    required MeshRepository repository,
    required LocalMeshTransportService transport,
    DeltaApplier? applier,
  })  : _repository = repository,
        _transport = transport,
        _applier = applier;

  final MeshRepository _repository;
  final LocalMeshTransportService _transport;

  /// Materialization hook (CrdtMaterializer in production). Invoked after
  /// durable append and BEFORE onNewDeltasPersisted fires, so listeners
  /// always observe post-fold intent rows.
  final DeltaApplier? _applier;

  final ValueNotifier<MeshEngineState> _state =
      ValueNotifier(const MeshEngineState());

  /// Read-only reactive state for the UI layer. Exposed as
  /// ValueListenable so consumers cannot mutate engine state.
  ValueListenable<MeshEngineState> get state => _state;

  /// Fires after every ingestion round that actually wrote rows — the
  /// signal for the UI/query layer to re-run intent materialization and
  /// semantic matching. Carries the count of newly persisted deltas.
  Stream<int> get onNewDeltasPersisted => _newDeltasController.stream;
  final _newDeltasController = StreamController<int>.broadcast();

  /// Detailed counterpart carrying the newly persisted rows themselves.
  /// Consumers that must RELAY deltas onward (e.g. the Core Node bridge
  /// server pushing to Light Clients) subscribe here; UI consumers should
  /// prefer the cheap count stream above.
  Stream<List<CrdtStateLog>> get onDeltasSynced => _syncedController.stream;
  final _syncedController = StreamController<List<CrdtStateLog>>.broadcast();

  /// publicKey → last transport state, for connected-set derivation and
  /// for suppressing duplicate anti-entropy rounds on repeated
  /// `connected` events (RSSI refreshes re-emit the same state).
  final Map<String, MeshNodeState> _peerStates = {};
  final Map<String, NodeIdentity> _peerIdentities = {};

  /// Serialized execution lane for sync rounds and ingestion: overlapping
  /// anti-entropy pushes would interleave transport writes and double-send
  /// batches. Each task chains onto the previous one.
  Future<void> _taskQueue = Future<void>.value();

  StreamSubscription<NodeDiscoveryEvent>? _discoverySubscription;
  StreamSubscription<List<CrdtStateLog>>? _deltaSubscription;
  bool _running = false;
  bool _disposed = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Boots the engine: loads the persisted clock, wires transport streams,
  /// and starts discovery. Throws [UnverifiedBridgeException] (web) or
  /// [MeshUnreachableException] (native radio failure) — the caller owns
  /// surfacing pairing/permission UI for those.
  Future<void> start({required NodeIdentity selfIdentity}) async {
    _checkNotDisposed();
    if (_running) return;
    _running = true;

    final initialClock = await _repository.currentLamportClock();
    _publish(_state.value.copyWith(
      connectionState: MeshConnectionState.connecting,
      localClock: initialClock,
      syncStatus: MeshSyncStatus.idle,
      clearError: true,
    ));

    // Subscribe BEFORE startDiscovery: transports may emit the verified
    // bridge event synchronously with handshake completion, and missing
    // it would leave connectionState stuck in `connecting`.
    _discoverySubscription = _transport.onNodeDiscovered.listen(
      _handleDiscoveryEvent,
      onError: _handleTransportError,
    );
    _deltaSubscription = _transport.onDeltaReceived.listen(
      _handleInboundDeltas,
      onError: _handleTransportError,
    );

    try {
      await _transport.startDiscovery(selfIdentity: selfIdentity);
    } on Object {
      await _teardownSubscriptions();
      _running = false;
      _publish(_state.value.copyWith(
        connectionState: MeshConnectionState.disconnected,
        syncStatus: MeshSyncStatus.error,
        lastError: 'Transport failed to start.',
      ));
      rethrow;
    }
  }

  Future<void> stop() async {
    _checkNotDisposed();
    if (!_running) return;
    _running = false;
    await _teardownSubscriptions();
    await _transport.stopDiscovery();
    _peerStates.clear();
    _peerIdentities.clear();
    _publish(_state.value.copyWith(
      connectionState: MeshConnectionState.disconnected,
      verifiedPeers: const [],
      syncStatus: MeshSyncStatus.idle,
      clearError: true,
    ));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    if (_running) {
      await stop();
    }
    _disposed = true;
    await _newDeltasController.close();
    await _syncedController.close();
    _state.dispose();
  }

  Future<void> _teardownSubscriptions() async {
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
    await _deltaSubscription?.cancel();
    _deltaSubscription = null;
  }

  // -------------------------------------------------------------------------
  // Local publication path (called by the app layer when the user creates
  // an operation): persist first, then gossip. Durability before network.
  // -------------------------------------------------------------------------

  /// Persists locally-authored deltas and gossips them to the mesh.
  /// Returns the Lamport clock after persistence. Transport unavailability
  /// is NOT an error here — rows are durable and will flow out during the
  /// next anti-entropy round (store-and-forward).
  Future<int> publishLocalDeltas(List<CrdtStateLog> deltas) async {
    _checkNotDisposed();
    if (deltas.isEmpty) return _state.value.localClock;

    final written = await _repository.appendDeltas(deltas);
    if (written > 0 && _applier != null) {
      // Fold locally authored ops into intent rows before anyone is told
      // about them — the rematch triggered by onNewDeltasPersisted must
      // see post-fold state.
      await _applier.applyDeltas(deltas);
    }
    final clock = await _repository.currentLamportClock();
    _publish(_state.value.copyWith(localClock: clock, clearError: true));

    if (written > 0) {
      _enqueue(() => _gossip(deltas));
      _newDeltasController.add(written);
      _syncedController.add(List.unmodifiable(deltas));
    }
    return clock;
  }

  // -------------------------------------------------------------------------
  // Anti-entropy: new verified peer → push local log in bounded batches
  // -------------------------------------------------------------------------

  void _handleDiscoveryEvent(NodeDiscoveryEvent event) {
    final key = event.node.cryptographicPublicKey;
    final previous = _peerStates[key];

    if (event.state == MeshNodeState.lost) {
      _peerStates.remove(key);
      _peerIdentities.remove(key);
    } else {
      _peerStates[key] = event.state;
      // Keep the richest identity we've seen (alias may arrive late).
      if (event.node.localAlias.isNotEmpty ||
          !_peerIdentities.containsKey(key)) {
        _peerIdentities[key] = event.node;
      }
    }

    _publishConnectionSnapshot();

    // Anti-entropy fires exactly on the transition INTO connected —
    // repeated `connected` events (RSSI refreshes) must not re-push the
    // entire log over a battery-powered radio.
    final becameConnected = event.state == MeshNodeState.connected &&
        previous != MeshNodeState.connected;
    if (becameConnected) {
      _enqueue(() => _runAntiEntropyRound(key));
    }
  }

  Future<void> _runAntiEntropyRound(String peerPublicKey) async {
    if (!_running || _disposed) return;
    if (_peerStates[peerPublicKey] != MeshNodeState.connected) {
      return; // Peer dropped while queued — round is moot.
    }

    _publish(_state.value.copyWith(syncStatus: MeshSyncStatus.syncing));
    try {
      // Push-based anti-entropy baseline: stream our full causal log to
      // the new peer in bounded batches. Their appendDeltas idempotency
      // discards everything they already hold, so over-sending is only a
      // bandwidth cost, never a correctness one. (Digest exchange to trim
      // that cost requires a summary frame in the wire protocol — flagged
      // in the delivery notes.)
      var cursorClock = -1; // Lamport clocks start at 0 ⇒ -1 selects all.
      while (_running && !_disposed) {
        final batch = await _repository.readDeltasSince(cursorClock);
        if (batch.isEmpty) break;

        final chunk = batch.length > _kSyncBatchSize
            ? batch.sublist(0, _kSyncBatchSize)
            : batch;
        await _transport.sendDeltaToPeer(peerPublicKey, chunk);

        if (chunk.length == batch.length) break; // Log fully streamed.
        cursorClock = chunk.last.lamportLogicalClock;
        // readDeltasSince is strictly-greater-than: equal-clock siblings of
        // the chunk boundary could be skipped. Step back one so the next
        // read re-covers the boundary clock; idempotency dedupes overlap.
        cursorClock -= 1;
      }
      _publish(_state.value.copyWith(
        syncStatus: MeshSyncStatus.idle,
        clearError: true,
      ));
    } on MeshUnreachableException catch (e) {
      // Peer vanished mid-round. Rows are durable; the next connectivity
      // window retries. This is degraded, not broken.
      _publish(_state.value.copyWith(
        syncStatus: MeshSyncStatus.error,
        lastError: 'Anti-entropy interrupted: ${e.message}',
      ));
    }
  }

  // -------------------------------------------------------------------------
  // Reactive ingestion: inbound deltas → persist → notify → re-gossip
  // -------------------------------------------------------------------------

  void _handleInboundDeltas(List<CrdtStateLog> deltas) {
    if (deltas.isEmpty) return;
    _enqueue(() => _ingest(deltas));
  }

  Future<void> _ingest(List<CrdtStateLog> deltas) async {
    if (!_running || _disposed) return;

    _publish(_state.value.copyWith(syncStatus: MeshSyncStatus.syncing));
    try {
      final written = await _repository.appendDeltas(deltas);

      if (written > 0) {
        // Order matters: (1) identify what was new, (2) fold it into
        // intent rows, (3) only then notify — listeners re-run ring
        // matching and must observe post-fold state, and (4) gossip.
        final newOnes = await _selectNewlyWritten(deltas);
        if (_applier != null) {
          await _applier.applyDeltas(newOnes);
        }

        final clock = await _repository.currentLamportClock();
        _publish(_state.value.copyWith(
          localClock: clock,
          syncStatus: MeshSyncStatus.idle,
          clearError: true,
        ));
        // UI refresh trigger — fired ONLY when rows were actually written.
        // Redelivered duplicates (the common gossip case) must not cause
        // re-materialization churn in the view layer.
        _newDeltasController.add(written);
        _syncedController.add(List.unmodifiable(newOnes));

        // Flood-gossip propagation: forward only what was NEW to us.
        // Because every node forwards a given delta at most once (only on
        // first write), propagation terminates in O(diameter) hops with no
        // echo storms — idempotency is the loop breaker.
        await _gossip(newOnes);
      } else {
        _publish(_state.value.copyWith(
          syncStatus: MeshSyncStatus.idle,
          clearError: true,
        ));
      }
    } on Object catch (e) {
      _publish(_state.value.copyWith(
        syncStatus: MeshSyncStatus.error,
        lastError: 'Ingestion failed: $e',
      ));
    }
  }

  /// appendDeltas reports a count, not identities; re-derive the newly
  /// written subset by clock position. Deltas at or below the pre-ingest
  /// clock could still be new (concurrent forks share clock values), so
  /// this filter is conservative-inclusive and relies on peer idempotency.
  Future<List<CrdtStateLog>> _selectNewlyWritten(
    List<CrdtStateLog> candidates,
  ) async {
    final persisted = <CrdtStateLog>[];
    for (final delta in candidates) {
      final log = await _repository.readCausalLog(delta.targetIntentUuid);
      final isPersisted =
          log.any((row) => row.transactionUuid == delta.transactionUuid);
      if (isPersisted) persisted.add(delta);
    }
    return persisted;
  }

  Future<void> _gossip(List<CrdtStateLog> deltas) async {
    if (deltas.isEmpty || !_running || _disposed) return;
    try {
      for (var i = 0; i < deltas.length; i += _kSyncBatchSize) {
        final end = (i + _kSyncBatchSize).clamp(0, deltas.length);
        await _transport.broadcastDelta(deltas.sublist(i, end));
      }
    } on MeshUnreachableException {
      // Zero peers right now. Rows are durable in Isar; they flow out on
      // the next anti-entropy round. Deliberately NOT an error state.
    }
  }

  // -------------------------------------------------------------------------
  // State publication
  // -------------------------------------------------------------------------

  void _publishConnectionSnapshot() {
    final connected = <NodeIdentity>[
      for (final entry in _peerStates.entries)
        if (entry.value == MeshNodeState.connected &&
            _peerIdentities[entry.key] != null)
          _peerIdentities[entry.key]!,
    ];

    _publish(_state.value.copyWith(
      verifiedPeers: List.unmodifiable(connected),
      connectionState: connected.isEmpty
          ? (_running
              ? MeshConnectionState.connecting
              : MeshConnectionState.disconnected)
          : MeshConnectionState.secureBridge,
    ));
  }

  void _handleTransportError(Object error) {
    // UnverifiedBridgeException lands here on web reconnect cycles;
    // native radio faults land here from the EventChannel. Both mean the
    // transport is no longer trustworthy/usable until user action.
    _peerStates.clear();
    _peerIdentities.clear();
    _publish(_state.value.copyWith(
      connectionState: MeshConnectionState.disconnected,
      verifiedPeers: const [],
      syncStatus: MeshSyncStatus.error,
      lastError: error.toString(),
    ));
  }

  void _publish(MeshEngineState next) {
    if (_disposed) return;
    _state.value = next;
  }

  void _enqueue(Future<void> Function() task) {
    // Chain onto the serialized lane; a failing task must not break the
    // chain for subsequent ones.
    _taskQueue = _taskQueue.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } on Object catch (e) {
        _publish(_state.value.copyWith(
          syncStatus: MeshSyncStatus.error,
          lastError: 'Engine task failed: $e',
        ));
      }
    });
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('MeshSyncEngine used after dispose()');
    }
  }
}
