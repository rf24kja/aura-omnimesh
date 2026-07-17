// lib/transport/bridge_server.dart
//
// Core Node WebSocket bridge serving Web Light Clients on the LAN.
//
// DELIBERATE ARCHITECTURE DECISION (deviation from "native bridge"):
// this server is pure Dart (dart:io), not Swift/Kotlin. The handshake
// requires signing with the node's Ed25519 private key — that key lives
// in Dart behind IdentitySigner, backed by Keychain/Keystore. A native
// bridge would need the private key exported across the platform channel,
// which is exactly the custody violation the signer interface exists to
// prevent. dart:io HttpServer runs natively on iOS/Android; the native
// layer keeps only what genuinely needs hardware access (radios, sensors).
//
// NOT compiled on web (dart:io) — Light Clients never import this file.
//
// Wire protocol (must mirror WebSocketLightClientTransport exactly):
//   client → bridge : helloChallenge{nonce, node}, broadcast{logs},
//                     unicast{peerPublicKey, logs}
//   bridge → client : helloResponse{publicKey, signature, alias},
//                     nodeState{node, state, rssi}, delta{logs}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../crypto/ed25519_signer.dart';
import '../domain/domain_models.dart';
import '../engine/mesh_sync_engine.dart';
import '../services/services.dart';
import 'hybrid_transport_service.dart'
    show
        crdtLogFromWire,
        crdtLogToWire,
        handshakeChallengePreimage;

/// A Light Client that has completed the challenge handshake.
class _BridgeClient {
  _BridgeClient(this.socket);
  final WebSocket socket;
  String? publicKey; // Set after helloChallenge (client-declared identity).
  bool greeted = false;
}

class CoreNodeBridgeServer {
  CoreNodeBridgeServer({
    required IdentitySigner signer,
    required NodeIdentity selfIdentity,
    required MeshSyncEngine engine,
    required LocalMeshTransportService transport,
    required MeshRepository repository,
    this.port = 7411,
  })  : _signer = signer,
        _selfIdentity = selfIdentity,
        _engine = engine,
        _transport = transport,
        _repository = repository;

  final IdentitySigner _signer;
  final NodeIdentity _selfIdentity;
  final MeshSyncEngine _engine;
  final LocalMeshTransportService _transport;
  final MeshRepository _repository;
  final int port;

  HttpServer? _server;
  final Set<_BridgeClient> _clients = {};
  StreamSubscription<List<CrdtStateLog>>? _deltaSubscription;
  StreamSubscription<NodeDiscoveryEvent>? _nodeSubscription;
  bool _running = false;
  bool _disposed = false;

  /// LAN endpoint to embed in the pairing QR: `ws://<thisDeviceIp>:<port>`.
  /// IP discovery is the pairing UI's job (NetworkInterface.list).
  Uri get advertisedEndpoint => Uri(scheme: 'ws', host: '0.0.0.0', port: port);

  Future<void> start() async {
    _checkNotDisposed();
    if (_running) return;
    _running = true;

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleHttpRequest, onError: (_) {});

    // Relay mesh traffic downstream. Radio-side deltas already flow into
    // the engine, and the engine's detailed stream covers BOTH sources
    // (radio ingest + locally authored), so one subscription suffices.
    _deltaSubscription = _engine.onDeltasSynced.listen(_relayDeltas);
    _nodeSubscription = _transport.onNodeDiscovered.listen(_relayNodeState);
  }

  Future<void> stop() async {
    _checkNotDisposed();
    if (!_running) return;
    _running = false;
    await _deltaSubscription?.cancel();
    await _nodeSubscription?.cancel();
    for (final client in _clients.toList()) {
      await client.socket.close(WebSocketStatus.goingAway);
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    if (_running) await stop();
    _disposed = true;
  }

  // ---------------------------------------------------------------------
  // Connection handling
  // ---------------------------------------------------------------------

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.upgradeRequired
        ..close();
      return;
    }
    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object {
      return; // Malformed upgrade — drop silently.
    }

    final client = _BridgeClient(socket);
    _clients.add(client);

    socket.listen(
      (frame) => _handleFrame(client, frame),
      onDone: () => _clients.remove(client),
      onError: (_) => _clients.remove(client),
      cancelOnError: true,
    );
  }

  Future<void> _handleFrame(_BridgeClient client, dynamic raw) async {
    if (raw is! String) return;
    final Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      frame = decoded;
    } on FormatException {
      return; // Malformed frame from one client never kills the server.
    }

    try {
      switch (frame['type']) {
        case 'helloChallenge':
          await _handleChallenge(client, frame);

        case 'broadcast' || 'unicast':
          // Handshake gate mirrors the client side: an ungreeted socket
          // gets no relay service.
          if (!client.greeted) return;
          final logs = (frame['logs'] as List)
              .map((e) => crdtLogFromWire(Map<String, dynamic>.from(e as Map)))
              .toList(growable: false);
          // Route through the engine: durable append (idempotent), fold
          // via the materializer, gossip to the radio mesh, and the
          // onDeltasSynced echo relays to OTHER Light Clients. Per-op
          // Ed25519 signatures are verified by the materializer — the
          // bridge does not vouch for content, only transports it.
          await _engine.publishLocalDeltas(logs);

        case 'syncRequest':
          // Anti-entropy for Light Clients: a late joiner pulls the
          // durable backlog instead of waiting for fresh gossip. Pull,
          // not push-on-hello — the client asks only after it has
          // VERIFIED this bridge, so no race with the handshake, and a
          // reconnecting client can pass its high-water clock.
          if (!client.greeted) return;
          final afterClock = frame['afterClock'];
          final backlog = await _repository
              .readDeltasSince(afterClock is int ? afterClock : 0);
          // Batched frames: one giant frame for a long history would
          // block the socket and spike Light Client frame decoding.
          const batchSize = 200;
          for (var i = 0; i < backlog.length; i += batchSize) {
            final end = (i + batchSize).clamp(0, backlog.length);
            client.socket.add(jsonEncode(<String, dynamic>{
              'type': 'delta',
              'logs': backlog
                  .sublist(i, end)
                  .map(crdtLogToWire)
                  .toList(growable: false),
            }));
          }

        default:
          break; // Forward-compatible: ignore unknown frame types.
      }
    } on Object {
      // A hostile frame (bad hex, wrong shapes) must not tear down the
      // bridge for every other paired client.
    }
  }

  /// Handshake steps 2–3 (server side): sign the domain-separated nonce
  /// preimage with THIS node's key and return identity + proof.
  Future<void> _handleChallenge(
    _BridgeClient client,
    Map<String, dynamic> frame,
  ) async {
    final nonceHex = frame['nonce'];
    if (nonceHex is! String) return;
    final nonce = decodeHex(nonceHex); // FormatException → outer catch.

    final signature = await _signer.signToHex(
      handshakeChallengePreimage(nonce),
    );

    // Register the client's declared identity so alias resolution works
    // mesh-side. Declared ≠ proven: the client's per-op signatures are
    // what actually authenticate its CRDT contributions.
    final node = frame['node'];
    if (node is Map) {
      final key = node['publicKey'];
      final alias = node['alias'];
      if (key is String && alias is String) {
        client.publicKey = key;
        final identity = NodeIdentity(
          cryptographicPublicKey: key,
          localAlias: alias,
          reliabilityScore: 0,
        );
        if (identity.hasValidKeyFormat) {
          await _repository.upsertNodeIdentity(identity);
        }
      }
    }

    client.greeted = true;
    client.socket.add(jsonEncode(<String, dynamic>{
      'type': 'helloResponse',
      'publicKey': _signer.publicKeyHex,
      'signature': signature,
      'alias': _selfIdentity.localAlias,
    }));
  }

  // ---------------------------------------------------------------------
  // Downstream relay
  // ---------------------------------------------------------------------

  void _relayDeltas(List<CrdtStateLog> deltas) {
    if (deltas.isEmpty || _clients.isEmpty) return;
    final frame = jsonEncode(<String, dynamic>{
      'type': 'delta',
      'logs': deltas.map(crdtLogToWire).toList(growable: false),
    });
    for (final client in _clients) {
      if (client.greeted) client.socket.add(frame);
    }
  }

  void _relayNodeState(NodeDiscoveryEvent event) {
    if (_clients.isEmpty) return;
    final frame = jsonEncode(<String, dynamic>{
      'type': 'nodeState',
      'node': <String, dynamic>{
        'publicKey': event.node.cryptographicPublicKey,
        'alias': event.node.localAlias,
      },
      'state': switch (event.state) {
        MeshNodeState.discovered => 'discovered',
        MeshNodeState.connecting => 'connecting',
        MeshNodeState.connected => 'connected',
        MeshNodeState.degraded => 'degraded',
        MeshNodeState.lost => 'lost',
      },
      'rssi': event.rssi,
    });
    for (final client in _clients) {
      if (client.greeted) client.socket.add(frame);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('CoreNodeBridgeServer used after dispose()');
    }
  }
}
