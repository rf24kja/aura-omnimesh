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
    this.reliabilityScore = 0,
  });

  final String publicKey;
  final String alias;

  /// Raw text of the offer this participant contributes to the loop.
  final String gives;
  final bool isSelf;

  /// Locally computed trust (ReliabilityScorer fold, 0–100). Zero for
  /// unknown or unproven peers — the UI stays silent rather than showing
  /// a fabricated number (fail-closed rendering).
  final int reliabilityScore;
}

/// One hop of a routed (accepted) ring with its materialized lock state.
class RoutedHopVm {
  const RoutedHopVm({
    required this.publicKey,
    required this.alias,
    required this.gives,
    required this.isSelf,
    required this.status,
  });

  final String publicKey;
  final String alias;
  final String gives;
  final bool isSelf;

  /// Materialized status of the hop's OFFER intent — already signature-
  /// and authorization-checked by the CRDT fold.
  final IntentStatus status;

  bool get committed =>
      status == IntentStatus.lockedInLoop || status == IntentStatus.satisfied;
}

/// A ring some participant has accepted (lock ops exist in the log),
/// tracked through confirmation to fulfilment.
class RoutedRingVm {
  const RoutedRingVm({
    required this.ringId,
    required this.hops,
    required this.involvesSelf,
    required this.confirmed,
    required this.completed,
    required this.broken,
    required this.canFulfil,
  });

  final String ringId;
  final List<RoutedHopVm> hops;
  final bool involvesSelf;

  /// Every hop has locked (or gone beyond) — the loop is agreed by all.
  final bool confirmed;

  /// Every hop reached `satisfied` — the exchange happened.
  final bool completed;

  /// A participant withdrew mid-flight; the loop cannot complete.
  final bool broken;

  /// This device may author satisfy ops now (own hops locked, ring
  /// confirmed, not yet fulfilled).
  final bool canFulfil;

  int get hopCount => hops.length;
  int get committedCount => hops.where((h) => h.committed).length;
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
    this.routedRings = const [],
    this.isMatching = false,
    this.lastError,
  });

  final MeshConnectionState connectionState;
  final MeshSyncStatus syncStatus;
  final int activePeersCount;
  final int localClock;
  final List<RingVm> discoveredRings;

  /// Accepted rings tracked to confirmation/fulfilment (lock ops in log).
  final List<RoutedRingVm> routedRings;

  final bool isMatching;
  final String? lastError;

  MeshUiState copyWith({
    MeshConnectionState? connectionState,
    MeshSyncStatus? syncStatus,
    int? activePeersCount,
    int? localClock,
    List<RingVm>? discoveredRings,
    List<RoutedRingVm>? routedRings,
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
        routedRings: routedRings ?? this.routedRings,
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
    this.onRingConfirmed,
    this.onRingCompleted,
  })  : _engine = engine,
        _repository = repository,
        _ringFacade = ringFacade,
        _signer = signer;

  final MeshSyncEngine _engine;
  final MeshRepository _repository;
  final RingMatchFacade _ringFacade;
  final IdentitySigner _signer;

  /// Fired once per ring when a SELF-involving ring transitions into the
  /// confirmed / completed phase. Plugin-free by design: the composition
  /// root decides what a notification looks like per platform.
  final void Function(RoutedRingVm ring)? onRingConfirmed;
  final void Function(RoutedRingVm ring)? onRingCompleted;

  /// ringId → last observed (confirmed, completed) pair, for edge
  /// detection. Session-scoped: a restart re-announces at most once.
  final Map<String, (bool, bool)> _ringPhases = {};

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
      final routed = await _assembleRoutedRings();
      if (_disposed) return;
      _publish(_state.value.copyWith(
        discoveredRings: List.unmodifiable(vms),
        routedRings: List.unmodifiable(routed),
        isMatching: false,
        clearError: true,
      ));
      _announcePhaseTransitions(routed);
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
      // Score is read fresh each rematch (never cached like aliases):
      // completed rings move it, and a stale trust figure at the accept
      // decision would be worse than none.
      final node = await _repository.findNodeByPublicKey(edge.providerKey);
      participants.add(RingParticipantVm(
        publicKey: edge.providerKey,
        alias: await _resolveAlias(edge.providerKey),
        gives: edge.offer.rawTextPayload,
        isSelf: edge.providerKey == self,
        reliabilityScore: node?.reliabilityScore ?? 0,
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
  // Routed rings: lock ops in the log, tracked to confirmation/fulfilment
  // -------------------------------------------------------------------------

  /// Scans the CRDT log for lock operations and assembles per-ring
  /// progress from MATERIALIZED intent rows (the fold already did the
  /// signature + authorization work — this is a pure read-side view).
  ///
  /// The full-log scan is deliberate Phase-1 simplicity: corpora are
  /// hundreds of rows, and the materializer re-folds full logs anyway. If
  /// this ever shows up in a profile, add a ringId-indexed query behind
  /// MeshRepository rather than caching here.
  Future<List<RoutedRingVm>> _assembleRoutedRings() async {
    final self = _signer.publicKeyHex;
    final log = await _repository.readDeltasSince(0);

    final ringIds = <String>{};
    for (final row in log) {
      final ringId = _lockRingIdOf(row);
      if (ringId != null) ringIds.add(ringId);
    }

    final vms = <RoutedRingVm>[];
    for (final ringId in ringIds.toList()..sort()) {
      // canonicalId encodes the ring's OFFER intent uuids in rotation-
      // canonical order — the id itself names the hops.
      final offerUuids = ringId.split('>');
      if (offerUuids.length < 2) continue;

      final hops = <RoutedHopVm>[];
      var missing = false;
      for (final uuid in offerUuids) {
        final offer = await _repository.findIntentByUuid(uuid);
        if (offer == null) {
          // Lock gossip outran create gossip — benign under partition;
          // the ring renders once the corpus catches up.
          missing = true;
          break;
        }
        hops.add(RoutedHopVm(
          publicKey: offer.originNodeKey,
          alias: await _resolveAlias(offer.originNodeKey),
          gives: offer.rawTextPayload,
          isSelf: offer.originNodeKey == self,
          status: offer.status,
        ));
      }
      if (missing) continue;

      final broken = hops.any((h) => h.status == IntentStatus.withdrawn);
      final confirmed = !broken && hops.every((h) => h.committed);
      final completed =
          !broken && hops.every((h) => h.status == IntentStatus.satisfied);
      final involvesSelf = hops.any((h) => h.isSelf);
      final selfDone = hops
          .where((h) => h.isSelf)
          .every((h) => h.status == IntentStatus.satisfied);

      vms.add(RoutedRingVm(
        ringId: ringId,
        hops: hops,
        involvesSelf: involvesSelf,
        confirmed: confirmed,
        completed: completed,
        broken: broken,
        canFulfil: involvesSelf && confirmed && !completed && !selfDone,
      ));
    }
    return vms;
  }

  /// Edge-detects confirmed/completed transitions for rings that involve
  /// this device and fires the composition-root callbacks exactly once
  /// per transition.
  void _announcePhaseTransitions(List<RoutedRingVm> routed) {
    for (final ring in routed) {
      final previous = _ringPhases[ring.ringId] ?? (false, false);
      _ringPhases[ring.ringId] = (ring.confirmed, ring.completed);
      if (!ring.involvesSelf) continue;
      if (ring.completed && !previous.$2) {
        onRingCompleted?.call(ring);
      } else if (ring.confirmed && !previous.$1) {
        onRingConfirmed?.call(ring);
      }
    }
  }

  /// Extracts the ringId from a lock/satisfy operation row, or null for
  /// every other row shape. Malformed payloads are ignored, not errors —
  /// the log accepts hostile input by design.
  String? _lockRingIdOf(CrdtStateLog row) {
    try {
      final decoded = jsonDecode(row.operationPayloadJson);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['op'] != 'lock_intent') return null;
      final ringId = decoded['ringId'];
      return ringId is String ? ringId : null;
    } on FormatException {
      return null;
    }
  }

  /// Authors satisfy operations for every intent THIS device locked into
  /// [ringId]. Callable only once the ring is confirmed (UI gate); the
  /// materializer enforces the real rules regardless.
  Future<void> satisfyRing(String ringId) async {
    _checkNotDisposed();
    final self = _signer.publicKeyHex;

    // Own lock ops name the intents to satisfy — including own NEED
    // intents, which the canonicalId (offers only) cannot name.
    final log = await _repository.readDeltasSince(0);
    final ownLockedUuids = <String>{};
    for (final row in log) {
      if (_lockRingIdOf(row) != ringId) continue;
      final decoded =
          jsonDecode(row.operationPayloadJson) as Map<String, dynamic>;
      if (decoded['author'] == self) {
        ownLockedUuids.add(row.targetIntentUuid);
      }
    }
    if (ownLockedUuids.isEmpty) {
      throw StateError(
        'This device locked no intents in ring $ringId — nothing to '
        'fulfil.',
      );
    }

    final pending = <String>[];
    for (final uuid in ownLockedUuids) {
      final intent = await _repository.findIntentByUuid(uuid);
      if (intent != null && intent.status == IntentStatus.lockedInLoop) {
        pending.add(uuid);
      }
    }
    if (pending.isEmpty) return; // Already satisfied — idempotent UX.
    pending.sort(); // Deterministic op order across devices.

    final baseClock = await _repository.currentLamportClock();
    final deltas = <CrdtStateLog>[];
    var offset = 1;
    for (final uuid in pending) {
      final payload = jsonEncode(<String, dynamic>{
        'op': 'satisfy_intent',
        'intentUuid': uuid,
        'ringId': ringId,
        'status': IntentStatus.satisfied.wireValue,
        'author': self,
      });
      final clock = baseClock + offset;
      offset += 1;
      deltas.add(CrdtStateLog(
        transactionUuid: secureUuidV4(),
        targetIntentUuid: uuid,
        authoritySignature: await _signer.signToHex(
          crdtSignaturePreimage(payload, clock),
        ),
        lamportLogicalClock: clock,
        operationPayloadJson: payload,
      ));
    }

    // Same single write path as acceptRing: durable append + fold + gossip
    // through the engine; never a direct row write beside it.
    await _engine.publishLocalDeltas(deltas);
    await _rematch();
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
