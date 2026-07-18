// lib/main.dart
//
// Composition root: the ONLY file that knows every concrete class. Wires
// storage → crypto → transport → engine → materializer → matcher → UI.
//
// Platform split at bootstrap:
//   Native (Core Mesh Node): Isar storage + platform-channel transport.
//   Web (Light Client): in-memory storage (ephemeral viewer — the Drift
//     wasm backend slots behind MeshRepository later) + WebSocket bridge
//     transport, endpoint taken from the ?bridge= URL parameter set by the
//     QR pairing flow.
//
// pubspec.yaml additions for this file:
//   dependencies:
//     flutter_secure_storage: ^9.0.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'compute/swarm_compute_gate.dart';
import 'crypto/ed25519_signer.dart';
import 'data/isar_mesh_repository.dart';
import 'domain/domain_models.dart';
import 'engine/crdt_materializer.dart';
import 'engine/mesh_sync_engine.dart';
import 'engine/reliability_scorer.dart';
import 'inference/onnx_embedding_service.dart';
import 'matching/ring_matcher.dart';
import 'services/services.dart';
import 'transport/bridge_handle.dart';
import 'transport/bridge_support.dart';
import 'transport/hybrid_transport_service.dart';
import 'ui/app_theme.dart';
import 'ui/dashboard_view.dart';
import 'ui/identity_gate.dart';
import 'ui/mesh_ui_adapter.dart';
import 'ui/permission_gate.dart';

// Local aliases of the design system tokens (app_theme.dart).
const Color _canvas = AuraColors.obsidian;
const Color _type = AuraColors.type;
const Color _border = AuraColors.slate;

const String _kSeedStorageKey = 'aura.identity.seed.v1';
const String kAliasStorageKey = 'aura.identity.alias.v1';

/// Load-or-create the device identity. Idempotent through secure
/// storage, so the onboarding identity screen and bootstrap() share ONE
/// custody path: whoever runs first creates the seed, the other reads
/// the same one. The seed itself never leaves platform secure storage.
Future<Ed25519IdentitySigner> loadOrCreateSigner() async {
  const secureStorage = FlutterSecureStorage();
  final storedSeed = await secureStorage.read(key: _kSeedStorageKey);
  if (storedSeed != null) {
    return Ed25519IdentitySigner.fromSeedHex(storedSeed);
  }
  final signer = await Ed25519IdentitySigner.generate();
  await secureStorage.write(
    key: _kSeedStorageKey,
    value: await signer.exportSeedHex(),
  );
  return signer;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AuraApp());
}

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

/// Everything the running app owns. Single dispose point.
class AppServices {
  AppServices({
    required this.repository,
    required this.signer,
    required this.selfIdentity,
    required this.transport,
    required this.engine,
    required this.adapter,
    required this.composer,
    required this.computeGate,
    required this.bridge,
    required this.scorer,
    required this.materializer,
    required this.inferenceLabel,
  });

  final MeshRepository repository;
  final Ed25519IdentitySigner signer;
  final NodeIdentity selfIdentity;
  final LocalMeshTransportService transport;
  final MeshSyncEngine engine;
  final MeshUiAdapter adapter;
  final IntentComposer composer;
  final SwarmComputeGate computeGate;

  /// Core Node LAN bridge (PLATFORM_SETUP §3); null on web Light Clients.
  final BridgeHandle? bridge;

  final ReliabilityScorer scorer;

  /// Sole intent-row writer; its counters feed the diagnostics surface.
  final CrdtMaterializer materializer;

  /// Which embedding backend won at boot (ONNX vs FNV fallback).
  final String inferenceLabel;

  Future<void> dispose() async {
    // Bridge first, before the engine, so client relays stop cleanly.
    await bridge?.dispose();
    await scorer.dispose();
    computeGate.stop();
    await adapter.dispose();
    await engine.dispose(); // Stops discovery internally.
    await transport.dispose();
    await computeGate.dispose();
    await repository.dispose();
  }
}

Future<AppServices> bootstrap() async {
  // --- 1. Identity: load-or-create the Ed25519 seed. ----------------------
  // Secure enclave-backed storage on native (Keychain/Keystore); on web,
  // flutter_secure_storage wraps WebCrypto-encrypted browser storage —
  // adequate for an ephemeral Light Client identity. The alias comes
  // from onboarding (IdentityGate); the key-derived name is the
  // fallback for pre-alias installs.
  final signer = await loadOrCreateSigner();
  const secureStorage = FlutterSecureStorage();
  final storedAlias = await secureStorage.read(key: kAliasStorageKey);

  final selfIdentity = NodeIdentity(
    cryptographicPublicKey: signer.publicKeyHex,
    localAlias: (storedAlias == null || storedAlias.trim().isEmpty)
        ? 'node-${signer.publicKeyHex.substring(0, 6)}'
        : storedAlias.trim(),
    reliabilityScore: 0,
  );

  // --- 2. Storage backend per platform. -----------------------------------
  final MeshRepository repository = kIsWeb
      ? InMemoryMeshRepository()
      : await IsarMeshRepository.open();
  await repository.upsertNodeIdentity(selfIdentity);

  // --- 3. Transport (web needs the pairing endpoint from the URL). --------
  Uri? bridgeEndpoint;
  if (kIsWeb) {
    final raw = Uri.base.queryParameters['bridge'];
    if (raw == null || raw.isEmpty) {
      throw const PairingRequiredException();
    }
    bridgeEndpoint = Uri.parse(raw);
    if (bridgeEndpoint.scheme != 'ws' && bridgeEndpoint.scheme != 'wss') {
      throw const PairingRequiredException();
    }
  }
  final transport =
      MeshTransportFactory.create(lightClientEndpoint: bridgeEndpoint);

  // --- 4. Engine + materializer + matcher + UI adapter. -------------------
  final materializer = CrdtMaterializer(repository);
  final engine = MeshSyncEngine(
    repository: repository,
    transport: transport,
    applier: materializer,
  );
  final ringFacade = RingMatchFacade(repository: repository);
  final notifier = await RingNotificationService.create();
  final adapter = MeshUiAdapter(
    engine: engine,
    repository: repository,
    ringFacade: ringFacade,
    signer: signer,
    onRingConfirmed: notifier?.ringConfirmed,
    onRingCompleted: notifier?.ringCompleted,
  );

  // --- 5. Inference: MiniLM ONNX everywhere, FNV surrogate as fallback. ---
  // The int32-surface model runs on native ORT and on the vendored wasm
  // runtime (web/ort/). A node that falls back to FNV publishes vectors
  // from a different embedding space — matching against MiniLM peers
  // degrades to near-zero similarity (missed rings, never false ones),
  // which is the acceptable failure direction.
  EdgeInferenceService inference;
  String inferenceLabel;
  final onnx = OnnxEmbeddingService();
  try {
    await onnx.warmUp();
    inference = onnx;
    inferenceLabel = 'ONNX MiniLM (multilingual)';
    if (kDebugMode) {
      // Cross-runtime parity beacon: must match the python int8 reference
      // (tool/trim_model.py output). The timer bounds the platform-thread
      // stall per embedding (the plugin runs session.run synchronously on
      // the Android main thread).
      final stopwatch = Stopwatch()..start();
      final beacon = await onnx.generateEmbedding('warm up');
      stopwatch.stop();
      debugPrint('aura-inference: ONNX MiniLM active, '
          '${stopwatch.elapsedMilliseconds}ms/embedding, '
          'beacon=${beacon.take(4).map((v) => v.toStringAsFixed(6)).join(',')}');
    }
  } on Object catch (e) {
    await onnx.dispose();
    inference = HashingEmbeddingService();
    await inference.warmUp();
    inferenceLabel = 'FNV fallback (degraded)';
    if (kDebugMode) {
      debugPrint('aura-inference: FNV fallback active ($e)');
    }
  }

  final composer = IntentComposer(
    engine: engine,
    repository: repository,
    signer: signer,
    inference: inference,
  );

  // --- 6. Compute gate (Module B): starts fail-closed, nothing trusted. ---
  final computeGate = SwarmComputeGate(trustedSsids: const {});
  await computeGate.start();

  // --- 7. Go live. ---------------------------------------------------------
  await adapter.attach();
  try {
    await engine.start(selfIdentity: selfIdentity);
  } on MeshUnreachableException {
    // Local-first: a dead radio stack is a degraded state, not a boot
    // failure. The engine has already published disconnected/error, so the
    // status strip honestly reads MESH: OFFLINE while the durable log and
    // store-and-forward keep working. UnverifiedBridgeException deliberately
    // stays fatal (fail-closed invariant: unverified bridge → terminate).
  }

  // --- 7b. Reputation fold: signed satisfied-ring history → scores. --------
  final scorer = ReliabilityScorer(repository)
    ..attachTo(engine.onNewDeltasPersisted);
  unawaited(scorer.recompute()); // Seed from already-persisted history.

  // --- 8. Core Node LAN bridge (PLATFORM_SETUP §3, native only). -----------
  BridgeHandle? bridge = createBridgeServer(
    signer: signer,
    selfIdentity: selfIdentity,
    engine: engine,
    transport: transport,
    repository: repository,
  );
  try {
    await bridge?.start();
  } on Object {
    // The LAN bridge is auxiliary (a bound :7411 from another instance must
    // not kill the node) — mesh radios and local state remain fully live.
    await bridge?.dispose();
    bridge = null;
  }

  return AppServices(
    repository: repository,
    signer: signer,
    selfIdentity: selfIdentity,
    transport: transport,
    engine: engine,
    adapter: adapter,
    composer: composer,
    computeGate: computeGate,
    bridge: bridge,
    scorer: scorer,
    materializer: materializer,
    inferenceLabel: inferenceLabel,
  );
}

/// Web launched without a ?bridge=ws://host:port pairing parameter.
class PairingRequiredException implements Exception {
  const PairingRequiredException();
}

// ---------------------------------------------------------------------------
// Ring lifecycle notifications (native only — the plugin has no web impl)
// ---------------------------------------------------------------------------

class RingNotificationService {
  RingNotificationService._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const AndroidNotificationDetails _details =
      AndroidNotificationDetails(
    'aura.rings',
    'Ring lifecycle',
    channelDescription:
        'Confirmation and completion of exchange rings you are part of.',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Returns null on web or if platform init fails — notifications are an
  /// enhancement, never a boot dependency (fail-open for UX, the protocol
  /// itself stays fail-closed).
  static Future<RingNotificationService?> create() async {
    if (kIsWeb) return null;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final initialized = await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // The permission gate / OS owns prompting; never at init.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      if (initialized != true) return null;
      return RingNotificationService._(plugin);
    } on Object {
      return null; // MissingPluginException in tests, unsupported targets.
    }
  }

  void ringConfirmed(RoutedRingVm ring) {
    unawaited(_show(
      id: ring.ringId.hashCode & 0x7fffffff,
      title: 'RING CONFIRMED',
      body: '${ring.hopCount}-party loop locked by everyone — '
          'fulfil your hop when the exchange happens.',
    ));
  }

  void ringCompleted(RoutedRingVm ring) {
    unawaited(_show(
      id: (ring.ringId.hashCode & 0x7fffffff) ^ 1,
      title: 'RING COMPLETED',
      body: 'All ${ring.hopCount} hops fulfilled. '
          'Reputation updated from the signed history.',
    ));
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _details),
      );
    } on Object {
      // A failed banner must never disturb the sync path.
    }
  }
}

// ---------------------------------------------------------------------------
// Intent composer: raw command line → embedded, signed create_intent op
// ---------------------------------------------------------------------------

class IntentComposer {
  IntentComposer({
    required MeshSyncEngine engine,
    required MeshRepository repository,
    required IdentitySigner signer,
    required EdgeInferenceService inference,
  })  : _engine = engine,
        _repository = repository,
        _signer = signer,
        _inference = inference;

  final MeshSyncEngine _engine;
  final MeshRepository _repository;
  final IdentitySigner _signer;
  final EdgeInferenceService _inference;

  /// Command grammar (spotlight line):
  ///   "need: a place to stay in March"  → IntentDirection.need
  ///   "offer: Dart consulting, 2h/week" → IntentDirection.offer
  ///   anything unprefixed               → offer (the generous default)
  Future<void> submitCommand(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final lower = trimmed.toLowerCase();
    final IntentDirection direction;
    final String text;
    if (lower.startsWith('need:') || lower.startsWith('need ')) {
      direction = IntentDirection.need;
      text = trimmed.substring(5).trim();
    } else if (lower.startsWith('offer:') || lower.startsWith('offer ')) {
      direction = IntentDirection.offer;
      text = trimmed.substring(6).trim();
    } else {
      direction = IntentDirection.offer;
      text = trimmed;
    }
    if (text.isEmpty) return;

    final embedding = await _inference.generateEmbedding(text);
    final intentUuid = secureUuidV4();

    // Payload schema must byte-match CrdtMaterializer._buildIntent.
    final payload = jsonStablePayload(
      op: 'create_intent',
      author: _signer.publicKeyHex,
      intent: <String, dynamic>{
        'intentUuid': intentUuid,
        'originNodeKey': _signer.publicKeyHex,
        'category': AllocationCategory.peerExchange.wireValue,
        'direction': direction.wireValue,
        'rawText': text,
        'vector': embedding,
        'quantity': 1,
        'epochMs': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
    );

    // Clock read is outside the engine's serialized lane; a concurrent
    // ingest can mint the same clock value. That is fine by design —
    // causalCompare's UUID tiebreak totally orders equal clocks.
    final clock = await _repository.currentLamportClock() + 1;

    await _engine.publishLocalDeltas([
      CrdtStateLog(
        transactionUuid: secureUuidV4(),
        targetIntentUuid: intentUuid,
        authoritySignature: await _signer.signToHex(
          crdtSignaturePreimage(payload, clock),
        ),
        lamportLogicalClock: clock,
        operationPayloadJson: payload,
      ),
    ]);
    if (kDebugMode) {
      debugPrint('aura-intent: published "$text" '
          '(${direction.wireValue}) clock=$clock');
    }
    // No direct row write: the engine's materializer folds the op into a
    // ResourceIntent row before publishLocalDeltas returns.
  }
}

// ---------------------------------------------------------------------------
// Deterministic fallback embeddings (feature hashing, FNV-1a)
// ---------------------------------------------------------------------------

class HashingEmbeddingService implements EdgeInferenceService {
  bool _warm = false;

  @override
  Future<void> warmUp() async {
    _warm = true; // No model to load — the "hardware" is arithmetic.
  }

  @override
  InferenceAccelerator get activeAccelerator =>
      InferenceAccelerator.cpuFallback;

  @override
  Future<List<double>> generateEmbedding(String input) async {
    if (!_warm) {
      throw StateError('generateEmbedding called before warmUp()');
    }

    final vector = List<double>.filled(kEmbeddingDimensions, 0.0);
    final tokens = input
        .toLowerCase()
        .split(RegExp(r'[^a-zа-я0-9]+'))
        .where((t) => t.length > 1)
        .toList(growable: false);

    // Unigrams + bigrams, signed feature hashing. FNV-1a instead of
    // String.hashCode: hashCode is NOT specified to be stable across Dart
    // runtimes, and cross-device embedding agreement is the entire point.
    void accumulate(String feature) {
      final h = _fnv1a(feature);
      final index = h % kEmbeddingDimensions;
      final sign = (h & 0x80000000) == 0 ? 1.0 : -1.0;
      vector[index] += sign;
    }

    for (var i = 0; i < tokens.length; i++) {
      accumulate(tokens[i]);
      if (i + 1 < tokens.length) {
        accumulate('${tokens[i]}_${tokens[i + 1]}');
      }
    }

    // L2 normalization per the interface contract (dot == cosine).
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    if (norm == 0.0) {
      // Degenerate input (all stop-length tokens): a fixed unit vector on
      // axis 0 — deterministic, never NaN.
      vector[0] = 1.0;
      return vector;
    }
    final inv = 1.0 / _sqrt(norm);
    for (var i = 0; i < vector.length; i++) {
      vector[i] *= inv;
    }
    return vector;
  }

  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static double _sqrt(double x) {
    var guess = x / 2;
    for (var i = 0; i < 16; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  @override
  Future<void> dispose() async {
    _warm = false;
  }
}

/// Stable JSON payload builder — key order is fixed by construction, so
/// signer and verifier hash identical bytes. jsonEncode preserves map
/// insertion order in Dart; this helper just makes that contract explicit
/// in one place.
String jsonStablePayload({
  required String op,
  required String author,
  Map<String, dynamic>? intent,
  Map<String, dynamic>? extra,
}) {
  final map = <String, dynamic>{
    'op': op,
    'author': author,
    'intent': ?intent,
    ...?extra,
  };
  return const JsonEncoder().convert(map);
}

// ---------------------------------------------------------------------------
// In-memory repository (web Light Client — ephemeral by design)
// ---------------------------------------------------------------------------

class InMemoryMeshRepository implements MeshRepository {
  final Map<String, NodeIdentity> _nodes = {};
  final Map<String, ResourceIntent> _intents = {};
  final Map<String, CrdtStateLog> _logs = {};
  final _nodesController =
      StreamController<List<NodeIdentity>>.broadcast();
  int _idCounter = 1;

  List<NodeIdentity> get _nodeSnapshot =>
      List.unmodifiable(_nodes.values.toList());

  @override
  Future<int> upsertNodeIdentity(NodeIdentity node) async {
    if (!node.hasValidKeyFormat) {
      throw FormatException(
        'Rejected NodeIdentity with malformed Ed25519 hex key: '
        '"${node.cryptographicPublicKey}"',
      );
    }
    final existing = _nodes[node.cryptographicPublicKey];
    node.id = existing?.id ?? _idCounter++;
    _nodes[node.cryptographicPublicKey] = node;
    _nodesController.add(_nodeSnapshot);
    return node.id;
  }

  @override
  Future<NodeIdentity?> findNodeByPublicKey(String publicKey) async =>
      _nodes[publicKey];

  @override
  Stream<List<NodeIdentity>> watchAllNodes() async* {
    yield _nodeSnapshot; // fireImmediately semantics.
    yield* _nodesController.stream;
  }

  @override
  Future<int> upsertIntent(ResourceIntent intent) async {
    if (intent.vectorData.length != kEmbeddingDimensions) {
      throw ArgumentError(
        'ResourceIntent.vectorData must be $kEmbeddingDimensions dims, '
        'got ${intent.vectorData.length}',
      );
    }
    final existing = _intents[intent.intentUuid];
    intent.id = existing?.id ?? _idCounter++;
    _intents[intent.intentUuid] = intent;
    return intent.id;
  }

  @override
  Future<ResourceIntent?> findIntentByUuid(String intentUuid) async =>
      _intents[intentUuid];

  @override
  Future<List<ResourceIntent>> readIntentsByCategory(
    AllocationCategory category, {
    IntentDirection? direction,
  }) async =>
      _intents.values
          .where((i) =>
              i.allocationCategory == category &&
              (direction == null || i.direction == direction))
          .toList(growable: false);

  @override
  Future<List<ResourceIntent>> semanticSearch(
    List<double> queryEmbedding, {
    int limit = 20,
    double minSimilarity = 0.35,
    AllocationCategory? category,
  }) async {
    if (queryEmbedding.length != kEmbeddingDimensions) {
      throw ArgumentError(
        'Query embedding must be $kEmbeddingDimensions dims, '
        'got ${queryEmbedding.length}',
      );
    }
    final scored = <({ResourceIntent intent, double score})>[];
    for (final intent in _intents.values) {
      if (category != null && intent.allocationCategory != category) {
        continue;
      }
      final score = intent.cosineSimilarity(queryEmbedding);
      if (score >= minSimilarity) scored.add((intent: intent, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored
        .take(limit)
        .map((e) => e.intent)
        .toList(growable: false);
  }

  @override
  Future<int> appendDeltas(List<CrdtStateLog> deltas) async {
    var written = 0;
    for (final delta in deltas) {
      if (_logs.containsKey(delta.transactionUuid)) continue;
      delta.id = _idCounter++;
      _logs[delta.transactionUuid] = delta;
      written += 1;
    }
    return written;
  }

  @override
  Future<List<CrdtStateLog>> readCausalLog(String targetIntentUuid) async {
    final rows = _logs.values
        .where((l) => l.targetIntentUuid == targetIntentUuid)
        .toList();
    rows.sort(CrdtStateLog.causalCompare);
    return rows;
  }

  @override
  Future<List<CrdtStateLog>> readDeltasSince(int afterLamportClock) async {
    final rows = _logs.values
        .where((l) => l.lamportLogicalClock > afterLamportClock)
        .toList();
    rows.sort(CrdtStateLog.causalCompare);
    return rows;
  }

  @override
  Future<int> currentLamportClock() async {
    var max = 0;
    for (final log in _logs.values) {
      if (log.lamportLogicalClock > max) max = log.lamportLogicalClock;
    }
    return max;
  }

  @override
  Future<void> dispose() async {
    await _nodesController.close();
  }
}

// ---------------------------------------------------------------------------
// App shell
// ---------------------------------------------------------------------------

class AuraApp extends StatefulWidget {
  const AuraApp({super.key});

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> {
  late final Future<AppServices> _boot = bootstrap();
  AppServices? _services;

  @override
  void dispose() {
    final services = _services;
    if (services != null) {
      unawaited(services.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura OmniMesh',
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.dark(),
      // Onboarding chain: radio permissions, then identity (alias +
      // public key). Both gate the FutureBuilder — reading _boot is what
      // starts bootstrap(), so the mesh node can race neither its
      // permissions nor its stored alias.
      home: PermissionGate(
        builder: (context) => IdentityGate(
          aliasStorageKey: kAliasStorageKey,
          loadSigner: loadOrCreateSigner,
          builder: (context) => FutureBuilder<AppServices>(
            future: _boot,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _BootErrorScreen(error: snapshot.error!);
              }
              final services = snapshot.data;
              if (services == null) {
                return const _BootScreen(label: 'INITIALIZING MESH NODE');
              }
              _services = services;
              return _Shell(services: services);
            },
          ),
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: DashboardView(
            adapter: services.adapter,
            computeGate: services.computeGate,
            repository: services.repository,
            onCommandSubmitted: services.composer.submitCommand,
            bridge: services.bridge,
          ),
        ),
        _StatusStrip(services: services),
      ],
    );
  }
}

/// One-line system strip: mesh + compute state at a glance, monochrome.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.services});

  final AppServices services;

  static const _labelStyle = TextStyle(
    color: _border,
    fontSize: 11,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  );

  String _connection(MeshConnectionState s) => switch (s) {
        MeshConnectionState.disconnected => 'OFFLINE',
        MeshConnectionState.connecting => 'SEARCHING',
        MeshConnectionState.secureBridge => 'SECURE',
      };

  String _compute(ComputeEligibility e) => switch (e) {
        ComputeEligibility.indeterminate => 'UNKNOWN',
        ComputeEligibility.discharging => 'ON BATTERY',
        ComputeEligibility.overheating => 'THERMAL BLOCK',
        ComputeEligibility.untrustedNetwork => 'UNTRUSTED NET',
        ComputeEligibility.eligible => 'READY',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Long-press opens the serverless diagnostics surface (ROADMAP
      // Phase 3): materializer counters, clock, peers, inference backend.
      behavior: HitTestBehavior.opaque,
      onLongPress: () => showDialog<void>(
        context: context,
        barrierColor: AuraColors.scrim,
        builder: (_) => _DiagnosticsDialog(services: services),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: _canvas,
          border: Border(top: BorderSide(color: _border, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: ValueListenableBuilder<MeshUiState>(
            valueListenable: services.adapter.state,
            builder: (context, mesh, _) {
              return ValueListenableBuilder<ComputeEligibility>(
                valueListenable: services.computeGate.eligibility,
                builder: (context, compute, _) {
                  return Text(
                    'MESH: ${_connection(mesh.connectionState)} · '
                    'PEERS: ${mesh.activePeersCount} · '
                    'CLOCK: ${mesh.localClock} · '
                    'COMPUTE: ${_compute(compute)}',
                    style: _labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Serverless diagnostics (ROADMAP Phase 3): the only window into mesh
/// health when there is no backend to query. Counters are read live on
/// each rebuild (REFRESH), and the alias is editable here — the one
/// post-onboarding place to rename this node.
class _DiagnosticsDialog extends StatefulWidget {
  const _DiagnosticsDialog({required this.services});

  final AppServices services;

  @override
  State<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<_DiagnosticsDialog> {
  static const _storage = FlutterSecureStorage();
  static const int _maxAliasLength = 24;

  late final TextEditingController _alias =
      TextEditingController(text: widget.services.selfIdentity.localAlias);
  bool _savingAlias = false;
  bool _aliasSaved = false;

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _saveAlias() async {
    final next = _alias.text.trim();
    if (next.isEmpty ||
        _savingAlias ||
        next == widget.services.selfIdentity.localAlias) {
      return;
    }
    setState(() => _savingAlias = true);
    await _storage.write(key: kAliasStorageKey, value: next);
    // selfIdentity is the SAME NodeIdentity instance the engine and the
    // bridge hold, so mutating localAlias updates every reader; persist
    // the row too. New handshakes and gossip carry the new alias; peers
    // already connected keep the old one until they reconnect (fine for
    // v1 — no forced re-announce).
    widget.services.selfIdentity.localAlias = next;
    await widget.services.repository
        .upsertNodeIdentity(widget.services.selfIdentity);
    if (!mounted) return;
    setState(() {
      _savingAlias = false;
      _aliasSaved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = _StatusStrip._labelStyle;
    final services = widget.services;
    final mesh = services.adapter.state.value;
    final materializer = services.materializer;
    final rows = <(String, String)>[
      ('PUBLIC KEY', services.signer.publicKeyHex),
      ('MESH', switch (mesh.connectionState) {
        MeshConnectionState.disconnected => 'OFFLINE',
        MeshConnectionState.connecting => 'SEARCHING',
        MeshConnectionState.secureBridge => 'SECURE',
      }),
      ('VERIFIED PEERS', '${mesh.activePeersCount}'),
      ('LAMPORT CLOCK', '${mesh.localClock}'),
      ('SYNC', mesh.syncStatus.name),
      ('INFERENCE', services.inferenceLabel),
      ('FOLDS', '${materializer.totalFolds}'),
      ('OPS APPLIED', '${materializer.totalApplied}'),
      ('REJECTED · SIG', '${materializer.totalRejectedSignatures}'),
      ('REJECTED · RULE', '${materializer.totalRejectedRule}'),
      ('BRIDGE', services.bridge == null ? '—' : 'HOSTING'),
      ('LAST ERROR', mesh.lastError ?? '—'),
    ];
    return Dialog(
      backgroundColor: _canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DIAGNOSTICS', style: labelStyle),
            const SizedBox(height: 16),

            // Editable alias — the one post-onboarding rename surface.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 150, child: Text('ALIAS', style: labelStyle)),
                Expanded(
                  child: TextField(
                    controller: _alias,
                    enabled: !_savingAlias,
                    cursorColor: AuraColors.type,
                    cursorWidth: 2,
                    style: const TextStyle(color: _type, fontSize: 13),
                    maxLength: _maxAliasLength,
                    onChanged: (_) {
                      if (_aliasSaved) setState(() => _aliasSaved = false);
                    },
                    onSubmitted: (_) => _saveAlias(),
                    decoration: const InputDecoration(
                      isDense: true,
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AuraColors.hairline,
                            width: AuraStroke.hair),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AuraColors.type, width: AuraStroke.hair),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _saveAlias,
                  child: Text(
                    _savingAlias ? '…' : (_aliasSaved ? 'SAVED' : 'SAVE'),
                    style: labelStyle.copyWith(
                      color: _aliasSaved ? AuraColors.emerald : _type,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 150, child: Text(k, style: labelStyle)),
                    Expanded(
                      child: Text(
                        v,
                        style: const TextStyle(
                          color: _type,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => setState(() {}),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: _border, width: 1),
                    ),
                  ),
                  child: Text('REFRESH',
                      style: labelStyle.copyWith(color: _type)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: Center(
        child: Text(label, style: _StatusStrip._labelStyle),
      ),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.error});

  final Object error;

  String get _message {
    if (error is PairingRequiredException) {
      return 'LIGHT CLIENT NOT PAIRED\n\n'
          'Open this PWA with ?bridge=ws://<core-node-ip>:<port>\n'
          'from the QR code shown on a Core Mesh Node.';
    }
    if (error is UnverifiedBridgeException) {
      return 'BRIDGE FAILED VERIFICATION\n\n'
          '${(error as UnverifiedBridgeException).message}\n'
          'Re-pair with a trusted Core Node.';
    }
    return 'BOOT FAILURE\n\n$error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _type, fontSize: 13, height: 1.6),
          ),
        ),
      ),
    );
  }
}
