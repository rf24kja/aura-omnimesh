// ReliabilityScorer: scores derive only from the local signed log, count
// distinct COMPLETED rings, and never fabricate identity rows.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/reliability_scorer.dart';
import 'package:omnimesh/main.dart';

void main() {
  late InMemoryMeshRepository repository;
  late CrdtMaterializer materializer;
  late ReliabilityScorer scorer;
  late List<Ed25519IdentitySigner> nodes;

  Future<CrdtStateLog> signedOp({
    required Ed25519IdentitySigner signer,
    required String targetUuid,
    required Map<String, dynamic> payloadMap,
    required int clock,
  }) async {
    final payload = jsonEncode(payloadMap);
    return CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: targetUuid,
      authoritySignature:
          await signer.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    );
  }

  setUp(() async {
    repository = InMemoryMeshRepository();
    materializer = CrdtMaterializer(repository);
    scorer = ReliabilityScorer(repository);
    nodes = [
      await Ed25519IdentitySigner.generate(),
      await Ed25519IdentitySigner.generate(),
      await Ed25519IdentitySigner.generate(),
    ];
    // All three identities are known peers on this device.
    for (final node in nodes) {
      await repository.upsertNodeIdentity(NodeIdentity(
        cryptographicPublicKey: node.publicKeyHex,
        localAlias: 'node-${node.publicKeyHex.substring(0, 6)}',
        reliabilityScore: 0,
      ));
    }
  });

  /// Builds a 3-hop ring: create 3 offers, then per stage lock/satisfy
  /// them, folding through the materializer after each batch.
  Future<String> driveRing({required bool throughSatisfy}) async {
    final offerUuids = <String>[];
    for (var i = 0; i < 3; i++) {
      final uuid = secureUuidV4();
      offerUuids.add(uuid);
      final vector = List<double>.filled(kEmbeddingDimensions, 0.0)
        ..[i] = 1.0;
      final delta = await signedOp(
        signer: nodes[i],
        targetUuid: uuid,
        payloadMap: {
          'op': 'create_intent',
          'author': nodes[i].publicKeyHex,
          'intent': {
            'intentUuid': uuid,
            'originNodeKey': nodes[i].publicKeyHex,
            'category': 'peer_exchange',
            'direction': 'offer',
            'rawText': 'offer $i',
            'vector': vector,
            'quantity': 1,
            'epochMs': 1000 + i,
          },
        },
        clock: 1,
      );
      await repository.appendDeltas([delta]);
      await materializer.applyDeltas([delta]);
    }

    // canonicalId: rotate to the lexicographically smallest offer uuid.
    var best = 0;
    for (var i = 1; i < offerUuids.length; i++) {
      if (offerUuids[i].compareTo(offerUuids[best]) < 0) best = i;
    }
    final ringId = [
      ...offerUuids.sublist(best),
      ...offerUuids.sublist(0, best),
    ].join('>');

    Future<void> stage(String op, String status, int clock) async {
      for (var i = 0; i < 3; i++) {
        final delta = await signedOp(
          signer: nodes[i],
          targetUuid: offerUuids[i],
          payloadMap: {
            'op': op,
            'intentUuid': offerUuids[i],
            'ringId': ringId,
            'status': status,
            'author': nodes[i].publicKeyHex,
          },
          clock: clock,
        );
        await repository.appendDeltas([delta]);
        await materializer.applyDeltas([delta]);
      }
    }

    await stage('lock_intent', 'locked_in_loop', 2);
    if (throughSatisfy) {
      await stage('satisfy_intent', 'satisfied', 3);
    }
    return ringId;
  }

  test('locked-but-unfinished ring scores nothing', () async {
    await driveRing(throughSatisfy: false);
    final scores = await scorer.recompute();
    expect(scores, isEmpty);
    for (final node in nodes) {
      final row = await repository.findNodeByPublicKey(node.publicKeyHex);
      expect(row!.reliabilityScore, 0);
    }
  });

  test('completed ring grants every hop owner +10, persisted', () async {
    await driveRing(throughSatisfy: true);
    final scores = await scorer.recompute();
    expect(scores.length, 3);
    for (final node in nodes) {
      expect(scores[node.publicKeyHex], ReliabilityScorer.pointsPerRing);
      final row = await repository.findNodeByPublicKey(node.publicKeyHex);
      expect(row!.reliabilityScore, ReliabilityScorer.pointsPerRing);
    }
  });

  test('two completed rings stack; recompute is idempotent', () async {
    await driveRing(throughSatisfy: true);
    await driveRing(throughSatisfy: true);
    final first = await scorer.recompute();
    final second = await scorer.recompute();
    expect(first, second);
    for (final node in nodes) {
      expect(first[node.publicKeyHex], 2 * ReliabilityScorer.pointsPerRing);
    }
  });

  test('unknown identities are scored but never fabricated as rows',
      () async {
    final ghost = await Ed25519IdentitySigner.generate();
    // Ring authored partly by a node we hold no identity row for.
    nodes[2] = ghost;
    await driveRing(throughSatisfy: true);
    final scores = await scorer.recompute();
    expect(scores[ghost.publicKeyHex], ReliabilityScorer.pointsPerRing);
    expect(await repository.findNodeByPublicKey(ghost.publicKeyHex), isNull);
  });
}
