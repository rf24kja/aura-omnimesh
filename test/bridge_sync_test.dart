// Late-joiner anti-entropy over the LAN bridge: a Light Client that
// connects AFTER intents were published must converge by pulling the
// durable backlog. Real CoreNodeBridgeServer on localhost, real
// dart:io WebSocket client, real Ed25519 — only the radio transport is
// faked.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/mesh_sync_engine.dart';
import 'package:omnimesh/main.dart';
import 'package:omnimesh/services/services.dart';
import 'package:omnimesh/transport/bridge_server.dart';
import 'package:omnimesh/transport/hybrid_transport_service.dart'
    show handshakeChallengePreimage;

class _FakeTransport implements LocalMeshTransportService {
  final _nodes = StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltas = StreamController<List<CrdtStateLog>>.broadcast();

  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered => _nodes.stream;
  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltas.stream;
  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> broadcastDelta(List<CrdtStateLog> elements) async {}
  @override
  Future<void> sendDeltaToPeer(
      String peerPublicKey, List<CrdtStateLog> elements) async {}
  @override
  Future<void> dispose() async {
    await _nodes.close();
    await _deltas.close();
  }
}

const _port = 7911;

void main() {
  late InMemoryMeshRepository repository;
  late MeshSyncEngine engine;
  late CoreNodeBridgeServer server;
  late Ed25519IdentitySigner coreSigner;
  final publishedTx = <String>[];
  final clockOf = <String, int>{};

  Future<void> publishIntent(int index) async {
    final uuid = 'intent-$index';
    final vector = List<double>.filled(kEmbeddingDimensions, 0.0)..[0] = 1.0;
    final payload = jsonStablePayload(
      op: 'create_intent',
      author: coreSigner.publicKeyHex,
      intent: <String, dynamic>{
        'intentUuid': uuid,
        'originNodeKey': coreSigner.publicKeyHex,
        'category': 'peer_exchange',
        'direction': 'offer',
        'rawText': 'offer $index',
        'vector': vector,
        'quantity': 1,
        'epochMs': 1000 + index,
      },
    );
    final clock = await repository.currentLamportClock() + 1;
    final txId = secureUuidV4();
    publishedTx.add(txId);
    clockOf[txId] = clock;
    await engine.publishLocalDeltas([
      CrdtStateLog(
        transactionUuid: txId,
        targetIntentUuid: uuid,
        authoritySignature: await coreSigner.signToHex(
          crdtSignaturePreimage(payload, clock),
        ),
        lamportLogicalClock: clock,
        operationPayloadJson: payload,
      ),
    ]);
  }

  setUpAll(() async {
    repository = InMemoryMeshRepository();
    coreSigner = await Ed25519IdentitySigner.generate();
    final transport = _FakeTransport();
    engine = MeshSyncEngine(
      repository: repository,
      transport: transport,
      applier: CrdtMaterializer(repository),
    );
    for (var i = 0; i < 5; i++) {
      await publishIntent(i);
    }
    server = CoreNodeBridgeServer(
      signer: coreSigner,
      selfIdentity: NodeIdentity(
        cryptographicPublicKey: coreSigner.publicKeyHex,
        localAlias: 'core',
        reliabilityScore: 0,
      ),
      engine: engine,
      transport: transport,
      repository: repository,
      port: _port,
    );
    await server.start();
  });

  tearDownAll(() async {
    await server.dispose();
  });

  Future<(WebSocket, Stream<Map<String, dynamic>>)> connect() async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$_port');
    final frames = ws
        .where((raw) => raw is String)
        .map((raw) => jsonDecode(raw as String) as Map<String, dynamic>)
        .asBroadcastStream();
    return (ws, frames);
  }

  Uint8List randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(32, (_) => rng.nextInt(256)));
  }

  test('late joiner pulls the full backlog after a verified handshake',
      () async {
    final (ws, frames) = await connect();
    final nonce = randomNonce();

    ws.add(jsonEncode({
      'type': 'helloChallenge',
      'nonce': encodeHex(nonce),
      'node': {'publicKey': 'ab' * 32, 'alias': 'late-joiner'},
    }));

    final hello = await frames
        .firstWhere((f) => f['type'] == 'helloResponse')
        .timeout(const Duration(seconds: 5));
    expect(
      await verifyEd25519Hex(
        message: handshakeChallengePreimage(nonce),
        signatureHex: hello['signature'] as String,
        publicKeyHex: hello['publicKey'] as String,
      ),
      isTrue,
      reason: 'bridge must prove its identity before any sync',
    );
    expect(hello['publicKey'], coreSigner.publicKeyHex);

    ws.add(jsonEncode({'type': 'syncRequest', 'afterClock': 0}));

    final received = <String>{};
    await for (final frame in frames.timeout(const Duration(seconds: 5))) {
      if (frame['type'] != 'delta') continue;
      for (final log in frame['logs'] as List) {
        received.add((log as Map)['txId'] as String);
      }
      if (received.length >= publishedTx.length) break;
    }
    expect(received, publishedTx.toSet());
    await ws.close();
  });

  test('afterClock high-water mark limits the replay (incremental resync)',
      () async {
    final (ws, frames) = await connect();
    ws.add(jsonEncode({
      'type': 'helloChallenge',
      'nonce': encodeHex(randomNonce()),
      'node': {'publicKey': 'cd' * 32, 'alias': 'resync'},
    }));
    await frames
        .firstWhere((f) => f['type'] == 'helloResponse')
        .timeout(const Duration(seconds: 5));

    // Ask only for what came after the third op's clock.
    final cutoff = clockOf[publishedTx[2]]!;
    ws.add(jsonEncode({'type': 'syncRequest', 'afterClock': cutoff}));

    final expected = publishedTx
        .where((tx) => clockOf[tx]! > cutoff)
        .toSet();
    final received = <String>{};
    await for (final frame in frames.timeout(const Duration(seconds: 5))) {
      if (frame['type'] != 'delta') continue;
      for (final log in frame['logs'] as List) {
        received.add((log as Map)['txId'] as String);
      }
      if (received.length >= expected.length) break;
    }
    expect(received, expected);
    await ws.close();
  });

  test('an ungreeted socket gets no backlog', () async {
    final (ws, frames) = await connect();
    final leaked = <Map<String, dynamic>>[];
    final sub = frames.listen(leaked.add);

    // No handshake — straight to the sync request.
    ws.add(jsonEncode({'type': 'syncRequest', 'afterClock': 0}));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(leaked.where((f) => f['type'] == 'delta'), isEmpty,
        reason: 'history must never leak to unauthenticated sockets');
    await sub.cancel();
    await ws.close();
  });

  test('hostile frames do not crash the bridge; it keeps serving', () async {
    // Blast the server with malformed input from one socket.
    final (bad, _) = await connect();
    for (final garbage in <String>[
      'not json at all',
      '[]', // valid json, wrong shape
      '{"type":"helloChallenge"}', // missing nonce
      '{"type":"helloChallenge","nonce":"zz","node":{}}', // bad hex nonce
      '{"type":"broadcast","logs":[{"txId":1}]}', // greeted-gate + bad log
      '{"type":"unknownFuture","x":1}', // unknown type
      jsonEncode({'type': 'syncRequest', 'afterClock': 'not-an-int'}),
    ]) {
      bad.add(garbage);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await bad.close();

    // A well-behaved client must still complete a handshake afterward.
    final (good, frames) = await connect();
    good.add(jsonEncode({
      'type': 'helloChallenge',
      'nonce': encodeHex(randomNonce()),
      'node': {'publicKey': 'ef' * 32, 'alias': 'survivor'},
    }));
    final hello = await frames
        .firstWhere((f) => f['type'] == 'helloResponse')
        .timeout(const Duration(seconds: 5));
    expect(hello['publicKey'], coreSigner.publicKeyHex);
    await good.close();
  });
}
