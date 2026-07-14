// lib/transport/hybrid_transport_service.dart
//
// Concrete LocalMeshTransportService implementations:
//   NativeCoreMeshTransport      — iOS/Android Core Mesh Node. Dart-side
//                                  orchestration over platform channels;
//                                  the Swift (Multipeer Connectivity) and
//                                  Kotlin (Nearby Connections) sides own the
//                                  radios and MTU chunking.
//   WebSocketLightClientTransport — Web PWA Light Client. Bridges into the
//                                  mesh via a Core Node running a local
//                                  WebSocket server on the same subnet.
//
// Platform selection uses kIsWeb (compile-time constant on web builds, so
// the native branch is tree-shaken out of the PWA bundle). No dart:io or
// dart:html imports: web_socket_channel abstracts the socket per platform,
// and package:cryptography's Ed25519 runs on all targets (pure Dart with
// WebCrypto acceleration where available).
//
// pubspec.yaml additions:
//   dependencies:
//     web_socket_channel: ^2.4.0
//     cryptography: ^2.7.0

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/domain_models.dart';
import '../services/services.dart';

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

abstract final class MeshTransportFactory {
  /// [lightClientEndpoint] is required on web (e.g. ws://192.168.1.42:7411,
  /// discovered via QR pairing with a Core Node) and ignored on native.
  static LocalMeshTransportService create({Uri? lightClientEndpoint}) {
    if (kIsWeb) {
      if (lightClientEndpoint == null) {
        throw ArgumentError(
          'Web Light Client requires a Core Node WebSocket endpoint. '
          'Obtain it from the pairing flow before constructing transport.',
        );
      }
      return WebSocketLightClientTransport(endpoint: lightClientEndpoint);
    }
    return NativeCoreMeshTransport();
  }
}

// ---------------------------------------------------------------------------
// Wire codec — shared by both implementations
// ---------------------------------------------------------------------------

Map<String, dynamic> crdtLogToWire(CrdtStateLog log) => <String, dynamic>{
      'txId': log.transactionUuid,
      'target': log.targetIntentUuid,
      'sig': log.authoritySignature,
      'clock': log.lamportLogicalClock,
      'op': log.operationPayloadJson,
    };

CrdtStateLog crdtLogFromWire(Map<String, dynamic> wire) {
  final txId = wire['txId'];
  final target = wire['target'];
  final sig = wire['sig'];
  final clock = wire['clock'];
  final op = wire['op'];
  if (txId is! String ||
      target is! String ||
      sig is! String ||
      clock is! int ||
      op is! String) {
    throw const FormatException('Malformed CrdtStateLog wire frame');
  }
  return CrdtStateLog(
    transactionUuid: txId,
    targetIntentUuid: target,
    authoritySignature: sig,
    lamportLogicalClock: clock,
    operationPayloadJson: op,
  );
}

NodeIdentity nodeIdentityFromWire(Map<String, dynamic> wire) {
  final key = wire['publicKey'];
  final alias = wire['alias'];
  if (key is! String || alias is! String) {
    throw const FormatException('Malformed NodeIdentity wire frame');
  }
  return NodeIdentity(
    cryptographicPublicKey: key,
    localAlias: alias,
    // Reliability is NEVER accepted from the wire — recomputed locally.
    reliabilityScore: 0,
  );
}

MeshNodeState meshNodeStateFromWire(String value) => switch (value) {
      'discovered' => MeshNodeState.discovered,
      'connecting' => MeshNodeState.connecting,
      'connected' => MeshNodeState.connected,
      'degraded' => MeshNodeState.degraded,
      'lost' => MeshNodeState.lost,
      _ => throw FormatException('Unknown MeshNodeState wire value: $value'),
    };

// ---------------------------------------------------------------------------
// Native Core Mesh Node (iOS Multipeer Connectivity / Android Nearby)
// ---------------------------------------------------------------------------

class NativeCoreMeshTransport implements LocalMeshTransportService {
  /// Channels are injectable for widget/unit tests via
  /// TestDefaultBinaryMessengerBinding; production code uses the defaults.
  NativeCoreMeshTransport({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ??
            const MethodChannel('aura.omnimesh/transport'),
        _events = eventChannel ??
            const EventChannel('aura.omnimesh/transport_events');

  final MethodChannel _methods;
  final EventChannel _events;

  final _discoveryController =
      StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltaController =
      StreamController<List<CrdtStateLog>>.broadcast();

  /// publicKey → last known transport state. Source of truth for the
  /// zero-peers check in [broadcastDelta].
  final Map<String, MeshNodeState> _peerStates = {};

  StreamSubscription<dynamic>? _eventSubscription;
  bool _active = false;
  bool _disposed = false;

  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered =>
      _discoveryController.stream;

  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltaController.stream;

  int get _connectedPeerCount => _peerStates.values
      .where((s) => s == MeshNodeState.connected)
      .length;

  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {
    _checkNotDisposed();
    if (_active) return; // Idempotent per interface contract.

    _eventSubscription = _events
        .receiveBroadcastStream()
        .listen(_handleNativeEvent, onError: _handleNativeError);

    try {
      // The native layer (MCNearbyServiceAdvertiser+Browser on iOS,
      // Nearby Connections P2P_CLUSTER on Android) starts advertising the
      // service id 'aura-omnimesh' with this identity as endpoint info.
      await _methods.invokeMethod<void>('startDiscovery', <String, dynamic>{
        'publicKey': selfIdentity.cryptographicPublicKey,
        'alias': selfIdentity.localAlias,
      });
      _active = true;
    } on PlatformException catch (e) {
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      throw MeshUnreachableException(
        'Radio stack failed to start: ${e.code} ${e.message ?? ''}',
      );
    }
  }

  @override
  Future<void> stopDiscovery() async {
    _checkNotDisposed();
    if (!_active) return; // Safe when inactive per interface contract.
    _active = false;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _peerStates.clear();
    try {
      await _methods.invokeMethod<void>('stopDiscovery');
    } on PlatformException {
      // Radios already down (app backgrounded, permission revoked) — the
      // Dart-side state is already cleared, so this is not an error path.
    }
  }

  @override
  Future<void> broadcastDelta(List<CrdtStateLog> elements) async {
    _checkNotDisposed();
    if (elements.isEmpty) return;
    if (!_active || _connectedPeerCount == 0) {
      throw const MeshUnreachableException(
        'No connected peers — batch must remain queued for the next '
        'connectivity window (store-and-forward).',
      );
    }
    final payload = jsonEncode(<String, dynamic>{
      'kind': 'crdt_delta',
      'logs': elements.map(crdtLogToWire).toList(growable: false),
    });
    try {
      // MTU chunking (BLE GATT ≈ 512 B/write) happens on the native side,
      // which knows the negotiated MTU per link. Dart hands over one blob.
      await _methods.invokeMethod<void>('broadcastPayload', <String, dynamic>{
        'payload': payload,
      });
    } on PlatformException catch (e) {
      throw MeshUnreachableException(
        'Broadcast rejected by radio layer: ${e.code} ${e.message ?? ''}',
      );
    }
  }

  @override
  Future<void> sendDeltaToPeer(
    String peerPublicKey,
    List<CrdtStateLog> elements,
  ) async {
    _checkNotDisposed();
    if (elements.isEmpty) return;
    if (_peerStates[peerPublicKey] != MeshNodeState.connected) {
      throw MeshUnreachableException(
        'Peer ${peerPublicKey.substring(0, 8)}… is not connected.',
      );
    }
    final payload = jsonEncode(<String, dynamic>{
      'kind': 'crdt_delta',
      'logs': elements.map(crdtLogToWire).toList(growable: false),
    });
    try {
      await _methods.invokeMethod<void>('sendPayloadToPeer', <String, dynamic>{
        'peerPublicKey': peerPublicKey,
        'payload': payload,
      });
    } on PlatformException catch (e) {
      throw MeshUnreachableException(
        'Unicast to peer failed: ${e.code} ${e.message ?? ''}',
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stopDiscovery();
    _disposed = true;
    await _discoveryController.close();
    await _deltaController.close();
  }

  // --- Native event plumbing ------------------------------------------------

  void _handleNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    final type = event['type'];

    try {
      switch (type) {
        case 'nodeState':
          final node = nodeIdentityFromWire(
            Map<String, dynamic>.from(event['node'] as Map),
          );
          final state = meshNodeStateFromWire(event['state'] as String);
          final rssi = (event['rssi'] as num?)?.toInt() ?? 0;

          if (state == MeshNodeState.lost) {
            _peerStates.remove(node.cryptographicPublicKey);
          } else {
            _peerStates[node.cryptographicPublicKey] = state;
          }
          _discoveryController.add(
            NodeDiscoveryEvent(node: node, state: state, rssi: rssi),
          );

        case 'payloadReceived':
          final decoded = jsonDecode(event['payload'] as String);
          if (decoded is! Map<String, dynamic>) break;
          if (decoded['kind'] != 'crdt_delta') break;
          final logs = (decoded['logs'] as List)
              .map((e) => crdtLogFromWire(Map<String, dynamic>.from(e as Map)))
              .toList(growable: false);
          // Signature-unverified by contract: the CRDT engine verifies
          // Ed25519 before persistence.
          _deltaController.add(logs);

        default:
          // Unknown event types from a newer native layer are ignored,
          // keeping the Dart side forward-compatible.
          break;
      }
    } on FormatException {
      // A malformed frame from one peer must not tear down the whole
      // transport stream — drop the frame, keep listening.
    }
  }

  void _handleNativeError(Object error) {
    // EventChannel errors indicate radio-level faults (Bluetooth off,
    // permission loss). Surface as universal peer loss so the router and
    // UI drop stale paths immediately.
    for (final entry in _peerStates.entries.toList(growable: false)) {
      _discoveryController.add(
        NodeDiscoveryEvent(
          node: NodeIdentity(
            cryptographicPublicKey: entry.key,
            localAlias: '',
            reliabilityScore: 0,
          ),
          state: MeshNodeState.lost,
          rssi: -127,
        ),
      );
    }
    _peerStates.clear();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('NativeCoreMeshTransport used after dispose()');
    }
  }
}

// ---------------------------------------------------------------------------
// Bridge handshake: exception, frame models, crypto primitives
// ---------------------------------------------------------------------------

/// Thrown when a bridge fails Ed25519 challenge-response verification
/// (bad signature, malformed response, or handshake timeout).
///
/// This is a TERMINAL trust failure, not a transient network fault: the
/// transport will NOT auto-reconnect to this endpoint. The caller must
/// surface a re-pairing flow to the user instead of retrying.
class UnverifiedBridgeException implements Exception {
  const UnverifiedBridgeException(this.message);
  final String message;

  @override
  String toString() => 'UnverifiedBridgeException: $message';
}

/// Domain separator prefixed to the nonce before signing. Prevents a
/// captured handshake signature from being replayed as a CRDT delta
/// signature (or vice versa) under the same keypair — cross-protocol
/// signature reuse is the classic failure mode of "just sign the nonce".
/// Preimage layout: utf8(domain) || 0x00 || nonceBytes.
const String _kHandshakeDomain = 'aura-omnimesh/bridge-hello/v1';

/// PUBLIC by design: the Core Node bridge server signs this exact
/// preimage; the Light Client verifies it. One definition, two callers.
Uint8List handshakeChallengePreimage(Uint8List nonce) {
  final domain = utf8.encode(_kHandshakeDomain);
  final out = Uint8List(domain.length + 1 + nonce.length);
  out.setRange(0, domain.length, domain);
  out[domain.length] = 0x00;
  out.setRange(domain.length + 1, out.length, nonce);
  return out;
}

/// 32 bytes from the platform CSPRNG (Random.secure maps to
/// crypto.getRandomValues on web, /dev/urandom-backed sources on native).
Uint8List _secureNonce([int length = 32]) {
  final rng = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rng.nextInt(256), growable: false),
  );
}

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List _hexToBytes(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    throw FormatException('Invalid hex string (length ${hex.length})');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Constant-time-ish Ed25519 verification via package:cryptography.
/// Returns false (never throws) on structurally invalid inputs so the
/// caller has exactly one failure path.
Future<bool> _verifyEd25519({
  required Uint8List message,
  required Uint8List signature,
  required Uint8List publicKey,
}) async {
  if (publicKey.length != 32 || signature.length != 64) return false;
  try {
    return await Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } on Object {
    return false;
  }
}

/// Client → bridge: opens the handshake with a fresh nonce.
class HelloChallengeFrame {
  const HelloChallengeFrame({
    required this.nonceHex,
    required this.clientPublicKey,
    required this.clientAlias,
  });

  final String nonceHex;
  final String clientPublicKey;
  final String clientAlias;

  Map<String, dynamic> toWire() => <String, dynamic>{
        'type': 'helloChallenge',
        'nonce': nonceHex,
        'node': <String, dynamic>{
          'publicKey': clientPublicKey,
          'alias': clientAlias,
        },
      };
}

/// Bridge → client: proves possession of the private key matching the
/// advertised identity by signing the domain-separated nonce preimage.
class HelloResponseFrame {
  const HelloResponseFrame({
    required this.publicKeyHex,
    required this.signatureHex,
    required this.alias,
  });

  final String publicKeyHex;
  final String signatureHex;
  final String alias;

  static HelloResponseFrame fromWire(Map<String, dynamic> wire) {
    final publicKey = wire['publicKey'];
    final signature = wire['signature'];
    final alias = wire['alias'];
    if (publicKey is! String || signature is! String || alias is! String) {
      throw const FormatException('Malformed helloResponse frame');
    }
    return HelloResponseFrame(
      publicKeyHex: publicKey.toLowerCase(),
      signatureHex: signature.toLowerCase(),
      alias: alias,
    );
  }
}

// ---------------------------------------------------------------------------
// Web PWA Light Client (WebSocket bridge to a Core Node on the LAN)
// ---------------------------------------------------------------------------

class WebSocketLightClientTransport implements LocalMeshTransportService {
  WebSocketLightClientTransport({
    required this.endpoint,
    this.maxReconnectAttempts = 8,
    this.baseBackoff = const Duration(milliseconds: 500),
    this.handshakeTimeout = const Duration(seconds: 5),
  });

  /// ws:// endpoint of the paired Core Node's local bridge server.
  final Uri endpoint;
  final int maxReconnectAttempts;
  final Duration baseBackoff;

  /// Window for the bridge to answer the challenge. Ed25519 signing is
  /// sub-millisecond even on old phones; a bridge that needs more than
  /// this on a LAN link is not a bridge worth trusting.
  final Duration handshakeTimeout;

  final _discoveryController =
      StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltaController =
      StreamController<List<CrdtStateLog>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  NodeIdentity? _selfIdentity;
  int _reconnectAttempt = 0;
  bool _active = false;
  bool _disposed = false;

  /// True only after Ed25519 verification succeeds. Every inbound
  /// nodeState/delta frame is gated on this flag.
  bool _bridgeVerified = false;

  /// Nonce awaiting a response; null when no handshake is in flight.
  /// Also serves as the replay guard: a helloResponse arriving with no
  /// pending nonce is dropped.
  Uint8List? _pendingNonce;
  Timer? _handshakeTimer;

  /// Resolves when the FIRST handshake verifies (or fails), so
  /// [startDiscovery] can throw [UnverifiedBridgeException] synchronously
  /// to its awaiter. Reconnect-cycle failures surface as stream errors on
  /// [onNodeDiscovered] instead, since no caller is awaiting them.
  Completer<void>? _firstHandshake;

  /// Verified bridge identity; nodeState events are trusted only as
  /// relayed-by this key.
  String? _verifiedBridgeKey;

  /// Ed25519 hex key of the currently verified Core Node bridge, or null
  /// when unverified. Surface this in the pairing UI so the user can
  /// visually match it against the QR-paired identity.
  String? get verifiedBridgeKey => _verifiedBridgeKey;

  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered =>
      _discoveryController.stream;

  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltaController.stream;

  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {
    _checkNotDisposed();
    if (_active) return;
    _active = true;
    _selfIdentity = selfIdentity;
    _reconnectAttempt = 0;
    _firstHandshake = Completer<void>();
    await _connect();
    // Block until the bridge proves key possession. A hostile or broken
    // bridge throws UnverifiedBridgeException here, before any caller
    // could have consumed a fabricated nodeState event.
    await _firstHandshake!.future;
  }

  Future<void> _connect() async {
    if (!_active || _disposed) return;

    final channel = WebSocketChannel.connect(endpoint);
    _channel = channel;
    _bridgeVerified = false;

    _socketSubscription = channel.stream.listen(
      _handleFrame,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );

    // --- Challenge-response handshake, step 1: issue the challenge. ---
    // Fresh CSPRNG nonce per connection attempt; a replayed old signature
    // can never verify against it.
    final self = _selfIdentity;
    if (self == null) {
      _failHandshake('startDiscovery invariant violated: no self identity.');
      return;
    }
    final nonce = _secureNonce();
    _pendingNonce = nonce;

    channel.sink.add(jsonEncode(
      HelloChallengeFrame(
        nonceHex: _bytesToHex(nonce),
        clientPublicKey: self.cryptographicPublicKey,
        clientAlias: self.localAlias,
      ).toWire(),
    ));

    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(handshakeTimeout, () {
      _failHandshake(
        'Bridge did not answer the challenge within '
        '${handshakeTimeout.inMilliseconds} ms.',
      );
    });
  }

  /// Terminal trust failure: tear down the socket, stop reconnecting, and
  /// surface [UnverifiedBridgeException] — to the startDiscovery awaiter if
  /// this was the first handshake, otherwise as an error on the discovery
  /// stream. Per the verification invariant, no automatic retry: the
  /// endpoint's identity is in question, not its reachability.
  void _failHandshake(String reason) {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _pendingNonce = null;
    _bridgeVerified = false;
    _verifiedBridgeKey = null;
    _active = false;

    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel?.sink.close();
    _channel = null;

    final error = UnverifiedBridgeException(reason);
    final first = _firstHandshake;
    if (first != null && !first.isCompleted) {
      first.completeError(error);
    } else if (!_discoveryController.isClosed) {
      _discoveryController.addError(error);
    }
  }

  void _scheduleReconnect() {
    // Transient transport loss (socket drop, Wi-Fi blip) — distinct from
    // _failHandshake: the bridge's identity isn't in question, so backoff
    // retry is correct. A fresh nonce is issued on every reconnect.
    _bridgeVerified = false;
    _pendingNonce = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    if (!_active || _disposed) return;

    if (_reconnectAttempt >= maxReconnectAttempts) {
      // Bridge is gone (Core Node left the subnet). Emit terminal loss so
      // the UI can prompt the user to re-pair; stay inactive until then.
      _active = false;
      _discoveryController.add(
        NodeDiscoveryEvent(
          node: NodeIdentity(
            cryptographicPublicKey: '0' * 64,
            localAlias: 'bridge',
            reliabilityScore: 0,
          ),
          state: MeshNodeState.lost,
          rssi: -127,
        ),
      );
      return;
    }

    // Exponential backoff with cap: 0.5s, 1s, 2s, 4s … ≤ 30s.
    final delayMs = baseBackoff.inMilliseconds * (1 << _reconnectAttempt);
    final delay = Duration(milliseconds: delayMs.clamp(0, 30000));
    _reconnectAttempt += 1;

    Future<void>.delayed(delay, () {
      if (_active && !_disposed) {
        _connect();
      }
    });
  }

  void _handleFrame(dynamic raw) {
    if (raw is! String) return;
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return; // Drop malformed frame; keep the socket alive.
    }
    if (decoded is! Map<String, dynamic>) return;

    try {
      switch (decoded['type']) {
        case 'helloResponse':
          // Async verification runs off the listener; failure paths all
          // funnel into _failHandshake, so the fire-and-forget is safe.
          unawaited(_processHelloResponse(decoded));

        case 'nodeState':
          // Verification gate: an unverified bridge cannot inject peers.
          if (!_bridgeVerified) return;
          final node = nodeIdentityFromWire(
            Map<String, dynamic>.from(decoded['node'] as Map),
          );
          final state = meshNodeStateFromWire(decoded['state'] as String);
          _discoveryController.add(NodeDiscoveryEvent(
            node: node,
            state: state,
            // Light Clients have no radio; the bridge relays its own link
            // quality proxy per peer.
            rssi: (decoded['rssi'] as num?)?.toInt() ?? 0,
          ));

        case 'delta':
          // Gated for hygiene, though deltas carry their own end-to-end
          // Ed25519 signatures verified by the CRDT engine regardless.
          if (!_bridgeVerified) return;
          final logs = (decoded['logs'] as List)
              .map((e) => crdtLogFromWire(Map<String, dynamic>.from(e as Map)))
              .toList(growable: false);
          _deltaController.add(logs);

        default:
          break;
      }
    } on FormatException {
      // Drop malformed frame; keep the socket alive.
    }
  }

  /// Handshake steps 3–4: verify the bridge's signature over the
  /// domain-separated nonce preimage against its advertised public key.
  Future<void> _processHelloResponse(Map<String, dynamic> decoded) async {
    final nonce = _pendingNonce;
    if (nonce == null) {
      // Unsolicited or duplicate response — replay attempt or bridge bug.
      // No challenge is outstanding, so there is nothing it could prove.
      return;
    }

    final HelloResponseFrame frame;
    final Uint8List signatureBytes;
    final Uint8List publicKeyBytes;
    try {
      frame = HelloResponseFrame.fromWire(decoded);
      signatureBytes = _hexToBytes(frame.signatureHex);
      publicKeyBytes = _hexToBytes(frame.publicKeyHex);
    } on FormatException catch (e) {
      _failHandshake('Malformed helloResponse: ${e.message}');
      return;
    }

    final verified = await _verifyEd25519(
      message: handshakeChallengePreimage(nonce),
      signature: signatureBytes,
      publicKey: publicKeyBytes,
    );

    // Re-check state after the async gap: the timeout timer or a socket
    // drop may have already torn the handshake down.
    if (_disposed || !_active || !identical(_pendingNonce, nonce)) return;

    if (!verified) {
      _failHandshake(
        'Bridge signature INVALID for advertised key '
        '${frame.publicKeyHex.substring(0, 8)}… — possible identity '
        'spoofing. Connection terminated; re-pair with a trusted Core Node.',
      );
      return;
    }

    // --- Verified: promote the connection. ---
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _pendingNonce = null;
    _verifiedBridgeKey = frame.publicKeyHex;
    _bridgeVerified = true;
    _reconnectAttempt = 0; // Healthy verified link resets backoff.

    _discoveryController.add(NodeDiscoveryEvent(
      node: NodeIdentity(
        cryptographicPublicKey: frame.publicKeyHex,
        localAlias: frame.alias,
        reliabilityScore: 0,
      ),
      state: MeshNodeState.connected,
      rssi: 0,
    ));

    final first = _firstHandshake;
    if (first != null && !first.isCompleted) {
      first.complete();
    }
  }

  @override
  Future<void> stopDiscovery() async {
    _checkNotDisposed();
    if (!_active) return;
    _active = false;
    _bridgeVerified = false;
    _verifiedBridgeKey = null;
    _pendingNonce = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  Future<void> broadcastDelta(List<CrdtStateLog> elements) async {
    _checkNotDisposed();
    if (elements.isEmpty) return;
    final channel = _channel;
    if (!_active || !_bridgeVerified || channel == null) {
      throw const MeshUnreachableException(
        'Light Client bridge is down or unverified — batch must remain '
        'queued locally until a verified bridge link exists.',
      );
    }
    channel.sink.add(jsonEncode(<String, dynamic>{
      'type': 'broadcast',
      'logs': elements.map(crdtLogToWire).toList(growable: false),
    }));
  }

  @override
  Future<void> sendDeltaToPeer(
    String peerPublicKey,
    List<CrdtStateLog> elements,
  ) async {
    _checkNotDisposed();
    if (elements.isEmpty) return;
    final channel = _channel;
    if (!_active || !_bridgeVerified || channel == null) {
      throw const MeshUnreachableException(
        'Light Client bridge is down or unverified — unicast unavailable.',
      );
    }
    channel.sink.add(jsonEncode(<String, dynamic>{
      'type': 'unicast',
      'peerPublicKey': peerPublicKey,
      'logs': elements.map(crdtLogToWire).toList(growable: false),
    }));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stopDiscovery();
    _disposed = true;
    await _discoveryController.close();
    await _deltaController.close();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('WebSocketLightClientTransport used after dispose()');
    }
  }
}
