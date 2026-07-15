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
import 'ui/mesh_ui_adapter.dart';
import 'ui/permission_gate.dart';

// Local aliases of the design system tokens (app_theme.dart).
const Color _canvas = AuraColors.obsidian;
const Color _type = AuraColors.type;
const Color _border = AuraColors.slate;

const String _kSeedStorageKey = 'aura.identity.seed.v1';

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
  // adequate for an ephemeral Light Client identity.
  const secureStorage = FlutterSecureStorage();
  final storedSeed = await secureStorage.read(key: _kSeedStorageKey);

  final Ed25519IdentitySigner signer;
  if (storedSeed == null) {
    signer = await Ed25519IdentitySigner.generate();
    await secureStorage.write(
      key: _kSeedStorageKey,
      value: await signer.exportSeedHex(),
    );
  } else {
    signer = await Ed25519IdentitySigner.fromSeedHex(storedSeed);
  }

  final selfIdentity = NodeIdentity(
    cryptographicPublicKey: signer.publicKeyHex,
    localAlias: 'node-${signer.publicKeyHex.substring(0, 6)}',
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

  // --- 5. Inference: MiniLM ONNX on native, FNV surrogate elsewhere. ------
  // Web Light Clients stay on the deterministic feature-hashing fallback
  // until the wasm execution provider is validated. A node that falls
  // back publishes vectors from a different embedding space — matching
  // against MiniLM peers degrades to near-zero similarity (missed rings,
  // never false ones), which is the acceptable failure direction.
  EdgeInferenceService inference;
  if (kIsWeb) {
    inference = HashingEmbeddingService();
    await inference.warmUp();
  } else {
    final onnx = OnnxEmbeddingService();
    try {
      await onnx.warmUp();
      inference = onnx;
      if (kDebugMode) {
        // Cross-runtime parity beacon: compare against the same model in
        // transformers.js — the first dims must agree to ~1e-3.
        final beacon = await onnx.generateEmbedding('warm up');
        debugPrint('aura-inference: ONNX MiniLM active, '
            'beacon=${beacon.take(4).map((v) => v.toStringAsFixed(6)).join(',')}');
      }
    } on Object catch (e) {
      await onnx.dispose();
      inference = HashingEmbeddingService();
      await inference.warmUp();
      if (kDebugMode) {
        debugPrint('aura-inference: FNV fallback active ($e)');
      }
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
      // Phase 0 onboarding: the Android radio permissions must be granted
      // before the gate builds the FutureBuilder — reading _boot is what
      // starts bootstrap(), so the mesh node cannot race its permissions.
      home: PermissionGate(
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
    return Container(
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
