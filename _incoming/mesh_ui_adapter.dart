// lib/ui/mesh_ui_adapter.dart
//
// Presentation adapter: the ONLY file allowed to know both the engine
// (MeshSyncEngine/RingMatchFacade) and the view contracts
// (DashboardState/VMs). Lives in the UI layer by design — the engine
// stays presentation-agnostic.
//
// Correction to the task spec: the engine exposes `onNewDeltasPersisted`
// (fires only when rows were ACTUALLY written), not `onEligibilityChanged`
// — eligibility belongs to SwarmComputeGate (Module B). This adapter wires
// the delta signal.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier;

import '../crypto/ed25519_signer.dart'
    show crdtSignaturePreimage, secureUuidV4;
import '../domain/domain_models.dart';
import '../engine/mesh_sync_engine.dart';
import '../matching/ring_matcher.dart';
import '../services/services.dart';

// ---------------------------------------------------------------------------
// Legacy dashboard contract (list-projection VMs)
// ---------------------------------------------------------------------------
// Owned HERE (not in dashboard_view.dart) so the dependency arrow points
// one way: view → adapter, never back. The tri-module DashboardView binds
// MeshUiState directly; this flattened projection remains for any simple
// list consumer.

class MatchedIntentVm {
  const MatchedIntentVm({
    required this.intentUuid,
    required this.title,
    required this.category,
    required this.similarity,
    required this.originAlias,
  });

  final String intentUuid;
  final String title;
  final AllocationCategory category;
  final double similarity;
  final String originAlias;
}

class NodeStateVm {
  const NodeStateVm({
    required this.publicKey,
    required this.alias,
    required this.state,
    required this.rssi,
  });

  final String publicKey;
  final String alias;
  final MeshNodeState state;
  final int rssi;
}

class DashboardState {
  const DashboardState({
    this.matchedIntents = const [],
    this.nodes = const [],
    this.isMatching = false,
  });

  final List<MatchedIntentVm> matchedIntents;
  final List<NodeStateVm> nodes;
  final bool isMatching;
}

/// Debounce window for rematching after delta ingestion. Gossip bursts
/// deliver many batches within milliseconds; recomputing the ring graph
/// per batch would burn CPU for identical results.
const Duration _kRematchDebounce = Duration(milliseconds: 300);

// ---------------------------------------------------------------------------
// Presentation models
// ---------------------------------------------------------------------------

class RingParticipantVm {
  const RingParticipantVm({
    required this.publicKey,
    required this.alias,
    required this.gives,
    required this.isSelf,
  });

  final String publicKey;
  final String alias;

  /// Raw text of the offer this participant contributes to the loop.
  final String gives;
  final bool isSelf;
}

class RingVm {
  const RingVm({
    required this.ringId,
    required this.participants,
    required this.matchStrength,
    required this.involvesSelf,
  });

  /// BarterRing.canonicalId — rotation-invariant, addressable in CRDT ops.
  final String ringId;

  /// Ordered around the loop: participants[i] gives to participants[i+1],
  /// the last gives back to the first.
  final List<RingParticipantVm> participants;

  /// Weakest-hop similarity in [0, 1] — same key the matcher ranks by.
  final double matchStrength;

  final bool involvesSelf;

  int get hopCount => participants.length;
}

/// Unified reactive UI state per the adapter contract.
class MeshUiState {
  const MeshUiState({
    this.connectionState = MeshConnectionState.disconnected,
    this.syncStatus = MeshSyncStatus.idle,
    this.activePeersCount = 0,
    this.localClock = 0,
    this.discoveredRings = const [],
    this.isMatching = false,
    this.lastError,
  });

  final MeshConnectionState connectionState;
  final MeshSyncStatus syncStatus;
  final int activePeersCount;
  final int localClock;
  final List<RingVm> discoveredRings;
  final bool isMatching;
  final String? lastError;

  MeshUiState copyWith({
    MeshConnectionState? connectionState,
    MeshSyncStatus? syncStatus,
    int? activePeersCount,
    int? localClock,
    List<RingVm>? discoveredRings,
    bool? isMatching,
    String? lastError,
    bool clearError = false,
  }) =>
      MeshUiState(
        connectionState: connectionState ?? this.connectionState,
        syncStatus: syncStatus ?? this.syncStatus,
        activePeersCount: activePeersCount ?? this.activePeersCount,
        localClock: localClock ?? this.localClock,
        discoveredRings: discoveredRings ?? this.discoveredRings,
        isMatching: isMatching ?? this.isMatching,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

// ---------------------------------------------------------------------------
// Adapter
// ---------------------------------------------------------------------------

class MeshUiAdapter {
  MeshUiAdapter({
    required MeshSyncEngine engine,
    required MeshRepository repository,
    required RingMatchFacade ringFacade,
    required IdentitySigner signer,
  })  : _engine = engine,
        _repository = repository,
        _ringFacade = ringFacade,
        _signer = signer;

  final MeshSyncEngine _engine;
  final MeshRepository _repository;
  final RingMatchFacade _ringFacade;
  final IdentitySigner _signer;

  final ValueNotifier<MeshUiState> _state =
      ValueNotifier(const MeshUiState());

  /// Primary reactive contract for any view layer.
  ValueListenable<MeshUiState> get state => _state;

  final ValueNotifier<DashboardState> _dashboardState =
      ValueNotifier(const DashboardState());

  /// Drop-in binding for the existing DashboardView (its `state` param).
  ValueListenable<DashboardState> get dashboardState => _dashboardState;

  /// Domain results of the last rematch, keyed by canonicalId — the
  /// acceptRing path needs the full BarterRing, not the flattened VM.
  final Map<String, BarterRing> _ringsById = {};

  /// publicKey → alias cache; identities are append-mostly, so a session
  /// cache avoids re-querying Isar per rematch.
  final Map<String, String> _aliasCache = {};

  StreamSubscription<int>? _deltaSubscription;
  Timer? _debounce;
  bool _attached = false;
  bool _disposed = false;
  bool _rematchRunning = false;
  bool _rematchQueued = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> attach() async {
    _checkNotDisposed();
    if (_attached) return;
    _attached = true;

    _engine.state.addListener(_onEngineState);
    _deltaSubscription = _engine.onNewDeltasPersisted.listen(
      (_) => _scheduleRematch(),
      onError: (Object e) => _publish(
        _state.value.copyWith(lastError: e.toString()),
      ),
    );

    _onEngineState(); // Seed from current engine snapshot.
    await _rematch(); // Initial ring pass over persisted state.
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    if (_attached) {
      _engine.state.removeListener(_onEngineState);
      await _deltaSubscription?.cancel();
    }
    _state.dispose();
    _dashboardState.dispose();
  }

  // -------------------------------------------------------------------------
  // Engine → UI projection
  // -------------------------------------------------------------------------

  void _onEngineState() {
    final engine = _engine.state.value;
    for (final peer in engine.verifiedPeers) {
      if (peer.localAlias.isNotEmpty) {
        _aliasCache[peer.cryptographicPublicKey] = peer.localAlias;
      }
    }
    _publish(_state.value.copyWith(
      connectionState: engine.connectionState,
      syncStatus: engine.syncStatus,
      activePeersCount: engine.verifiedPeers.length,
      localClock: engine.localClock,
      lastError: engine.lastError,
      clearError: engine.lastError == null,
    ));
  }

  void _scheduleRematch() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(_kRematchDebounce, () => unawaited(_rematch()));
  }

  Future<void> _rematch() async {
    if (_disposed) return;
    // Coalescing guard: if a rematch is in flight, remember that another
    // is wanted and run exactly one more afterwards — never two parallel
    // graph searches, never a lost trailing update.
    if (_rematchRunning) {
      _rematchQueued = true;
      return;
    }
    _rematchRunning = true;
    _publish(_state.value.copyWith(isMatching: true));

    try {
      final rings = await _ringFacade.findRings();
      final vms = <RingVm>[];
      _ringsById
        ..clear()
        ..addEntries(rings.map((r) => MapEntry(r.canonicalId, r)));
      for (final ring in rings) {
        vms.add(await _toRingVm(ring));
      }
      if (_disposed) return;
      _publish(_state.value.copyWith(
        discoveredRings: List.unmodifiable(vms),
        isMatching: false,
        clearError: true,
      ));
    } on Object catch (e) {
      if (_disposed) return;
      _publish(_state.value.copyWith(
        isMatching: false,
        lastError: 'Ring matching failed: $e',
      ));
    } finally {
      _rematchRunning = false;
      if (_rematchQueued && !_disposed) {
        _rematchQueued = false;
        unawaited(_rematch());
      }
    }
  }

  Future<RingVm> _toRingVm(BarterRing ring) async {
    final self = _signer.publicKeyHex;
    final participants = <RingParticipantVm>[];
    for (final edge in ring.edges) {
      participants.add(RingParticipantVm(
        publicKey: edge.providerKey,
        alias: await _resolveAlias(edge.providerKey),
        gives: edge.offer.rawTextPayload,
        isSelf: edge.providerKey == self,
      ));
    }
    return RingVm(
      ringId: ring.canonicalId,
      participants: participants,
      matchStrength: ring.minSimilarity,
      involvesSelf: participants.any((p) => p.isSelf),
    );
  }

  Future<String> _resolveAlias(String publicKey) async {
    final cached = _aliasCache[publicKey];
    if (cached != null) return cached;
    final node = await _repository.findNodeByPublicKey(publicKey);
    final alias = (node != null && node.localAlias.isNotEmpty)
        ? node.localAlias
        : '${publicKey.substring(0, 8)}…';
    _aliasCache[publicKey] = alias;
    return alias;
  }

  // -------------------------------------------------------------------------
  // Accept Ring: lock own intents + gossip signed CRDT ops
  // -------------------------------------------------------------------------

  /// Locks this device's intents inside [ringId] and gossips signed
  /// lock operations. Scope honesty: a device can only author status
  /// transitions for its OWN intents — other participants' locks arrive
  /// as their signed deltas. The ring is fully confirmed when lock ops
  /// exist for every hop (assembled by the CRDT materializer).
  ///
  /// Throws [StateError] if the ring vanished from the last match pass
  /// (stale UI tap after a rematch) — surface as a "ring expired" toast.
  Future<void> acceptRing(String ringId) async {
    _checkNotDisposed();
    final ring = _ringsById[ringId];
    if (ring == null) {
      throw StateError(
        'Ring $ringId is no longer available — the graph changed since it '
        'was displayed.',
      );
    }

    final self = _signer.publicKeyHex;
    final ownIntents = <ResourceIntent>{
      for (final edge in ring.edges)
        if (edge.offer.originNodeKey == self) edge.offer,
      for (final edge in ring.edges)
        if (edge.need.originNodeKey == self) edge.need,
    };
    if (ownIntents.isEmpty) {
      throw StateError(
        'This device owns no intents in ring $ringId — nothing to lock.',
      );
    }

    // Clock base once, then monotonic per operation. publishLocalDeltas
    // persists + gossips atomically from the caller's perspective (the
    // engine's serialized task lane orders it against ingestion).
    final baseClock = await _repository.currentLamportClock();
    final deltas = <CrdtStateLog>[];
    var offset = 1;

    for (final intent in ownIntents) {
      final payload = jsonEncode(<String, dynamic>{
        'op': 'lock_intent',
        'intentUuid': intent.intentUuid,
        'ringId': ringId,
        'status': IntentStatus.lockedInLoop.wireValue,
        'author': self,
      });
      final clock = baseClock + offset;
      offset += 1;

      deltas.add(CrdtStateLog(
        transactionUuid: secureUuidV4(),
        targetIntentUuid: intent.intentUuid,
        authoritySignature: await _signer.signToHex(
          crdtSignaturePreimage(payload, clock),
        ),
        lamportLogicalClock: clock,
        operationPayloadJson: payload,
      ));
    }

    // Single write path: publishLocalDeltas persists the ops AND the
    // engine's applier (CrdtMaterializer) folds them into intent rows
    // before returning. No optimistic direct upsert here — a second
    // writer racing the fold is how materialized views diverge.
    await _engine.publishLocalDeltas(deltas);

    // Locked intents left the open corpus — recompute immediately so the
    // accepted ring disappears from the feed without waiting for gossip.
    await _rematch();
  }

  // -------------------------------------------------------------------------
  // DashboardState projection (binds the existing DashboardView untouched)
  // -------------------------------------------------------------------------

  void _publish(MeshUiState next) {
    if (_disposed) return;
    _state.value = next;

    _dashboardState.value = DashboardState(
      isMatching: next.isMatching,
      nodes: [
        for (final peer in _engine.state.value.verifiedPeers)
          NodeStateVm(
            publicKey: peer.cryptographicPublicKey,
            alias: peer.localAlias.isNotEmpty
                ? peer.localAlias
                : '${peer.cryptographicPublicKey.substring(0, 8)}…',
            state: MeshNodeState.connected,
            rssi: 0,
          ),
      ],
      matchedIntents: [
        for (final ring in next.discoveredRings)
          MatchedIntentVm(
            // ringId rides in the intentUuid slot: DashboardView's
            // onIntentDispatched hands it back verbatim, so the app shell
            // wires (uuid, accept: true) → adapter.acceptRing(uuid).
            intentUuid: ring.ringId,
            title: ring.participants.map((p) => p.alias).join(' → '),
            category: AllocationCategory.peerExchange,
            similarity: ring.matchStrength,
            originAlias: '${ring.hopCount}-party loop',
          ),
      ],
    );
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('MeshUiAdapter used after dispose()');
    }
  }
}
