// Phase 1 determinism suite (CLAUDE.md invariant 3: determinism is a
// correctness property). Every check here must hold identically on every
// device, or peers diverge: signature preimages byte-for-byte, causal
// ordering, feature-hash embeddings, ring ranking, and the materializer
// fold.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/main.dart';
import 'package:omnimesh/matching/ring_matcher.dart';
import 'package:omnimesh/transport/hybrid_transport_service.dart'
    show handshakeChallengePreimage;

void main() {
  group('signature preimages', () {
    test('crdtSignaturePreimage is utf8(payload) || clock as 8 LE bytes', () {
      final preimage = crdtSignaturePreimage('{"a":1}', 0x0102);
      expect(
        preimage,
        Uint8List.fromList([
          ...utf8.encode('{"a":1}'),
          0x02, 0x01, 0, 0, 0, 0, 0, 0, // 258 little-endian, 8 bytes
        ]),
      );
    });

    test('crdtSignaturePreimage clock 0 and large web-safe clock', () {
      expect(
        crdtSignaturePreimage('', 0),
        Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]),
      );
      // 2^52 + 3 — near the top of the web-safe integer range.
      final big = crdtSignaturePreimage('', 4503599627370499);
      expect(big, hasLength(8));
      var reconstructed = 0;
      for (var i = 7; i >= 0; i--) {
        reconstructed = reconstructed * 256 + big[i];
      }
      expect(reconstructed, 4503599627370499);
    });

    test('handshakeChallengePreimage is domain || 0x00 || nonce', () {
      final nonce = Uint8List.fromList([9, 8, 7]);
      expect(
        handshakeChallengePreimage(nonce),
        Uint8List.fromList([
          ...utf8.encode('aura-omnimesh/bridge-hello/v1'),
          0x00,
          9, 8, 7,
        ]),
      );
    });
  });

  group('causal order', () {
    CrdtStateLog log(String tx, int clock) => CrdtStateLog(
          transactionUuid: tx,
          targetIntentUuid: 'i',
          authoritySignature: '',
          lamportLogicalClock: clock,
          operationPayloadJson: '{}',
        );

    test('clock dominates, uuid breaks ties, order is total', () {
      final a = log('aaaa', 5);
      final b = log('bbbb', 5);
      final c = log('cccc', 4);
      expect(CrdtStateLog.causalCompare(c, a), isNegative);
      expect(CrdtStateLog.causalCompare(a, b), isNegative);
      expect(CrdtStateLog.causalCompare(b, a), isPositive);
      expect(CrdtStateLog.causalCompare(a, a), 0);

      final shuffled = [b, a, c]..sort(CrdtStateLog.causalCompare);
      expect(shuffled.map((l) => l.transactionUuid), ['cccc', 'aaaa', 'bbbb']);
    });
  });

  group('hashing embeddings (FNV-1a)', () {
    // Independent reference implementation pinning the production
    // algorithm: unigrams + bigrams, signed feature hashing over FNV-1a
    // 32-bit, L2 normalization. If production ever drifts (e.g. to
    // String.hashCode), the vectors stop matching.
    List<double> reference(String input) {
      int fnv1a(String s) {
        var hash = 0x811c9dc5;
        for (final unit in s.codeUnits) {
          hash ^= unit;
          hash = (hash * 0x01000193) & 0xFFFFFFFF;
        }
        return hash;
      }

      final vector = List<double>.filled(kEmbeddingDimensions, 0.0);
      final tokens = input
          .toLowerCase()
          .split(RegExp(r'[^a-zа-я0-9]+'))
          .where((t) => t.length > 1)
          .toList(growable: false);
      void accumulate(String feature) {
        final h = fnv1a(feature);
        vector[h % kEmbeddingDimensions] +=
            (h & 0x80000000) == 0 ? 1.0 : -1.0;
      }

      for (var i = 0; i < tokens.length; i++) {
        accumulate(tokens[i]);
        if (i + 1 < tokens.length) {
          accumulate('${tokens[i]}_${tokens[i + 1]}');
        }
      }
      var norm = 0.0;
      for (final v in vector) {
        norm += v * v;
      }
      if (norm == 0.0) {
        vector[0] = 1.0;
        return vector;
      }
      var guess = norm / 2;
      for (var i = 0; i < 16; i++) {
        guess = (guess + norm / guess) / 2;
      }
      final inv = 1.0 / guess;
      for (var i = 0; i < vector.length; i++) {
        vector[i] *= inv;
      }
      return vector;
    }

    test('production embedding matches the reference bit-for-bit', () async {
      final service = HashingEmbeddingService();
      await service.warmUp();
      const input = 'offer: dart tutoring, 2h/week';
      expect(await service.generateEmbedding(input), reference(input));
    });

    test('two service instances agree; output is L2-normalized', () async {
      final s1 = HashingEmbeddingService();
      final s2 = HashingEmbeddingService();
      await s1.warmUp();
      await s2.warmUp();
      const input = 'need: помочь с флаттером';
      final v1 = await s1.generateEmbedding(input);
      final v2 = await s2.generateEmbedding(input);
      expect(v1, v2);
      var norm = 0.0;
      for (final x in v1) {
        norm += x * x;
      }
      expect(norm, closeTo(1.0, 1e-9));
    });

    test('degenerate input yields the fixed unit vector, never NaN',
        () async {
      final service = HashingEmbeddingService();
      await service.warmUp();
      final v = await service.generateEmbedding('a . ! %');
      expect(v[0], 1.0);
      expect(v.skip(1).every((x) => x == 0.0), isTrue);
    });
  });

  group('ring matcher', () {
    ResourceIntent intent({
      required String uuid,
      required String owner,
      required IntentDirection direction,
      required int axis,
    }) {
      final vector = List<double>.filled(kEmbeddingDimensions, 0.0)
        ..[axis] = 1.0;
      return ResourceIntent(
        intentUuid: uuid,
        originNodeKey: owner,
        allocationCategory: AllocationCategory.peerExchange,
        rawTextPayload: uuid,
        vectorData: vector,
        structuralQuantity: 1,
        epochTimestamp: 0,
        direction: direction,
      );
    }

    // 3-ring: A offers axis0 which B needs; B offers axis1 which C needs;
    // C offers axis2 which A needs.
    final corpus = [
      intent(uuid: 'a-off', owner: 'A', direction: IntentDirection.offer, axis: 0),
      intent(uuid: 'b-need', owner: 'B', direction: IntentDirection.need, axis: 0),
      intent(uuid: 'b-off', owner: 'B', direction: IntentDirection.offer, axis: 1),
      intent(uuid: 'c-need', owner: 'C', direction: IntentDirection.need, axis: 1),
      intent(uuid: 'c-off', owner: 'C', direction: IntentDirection.offer, axis: 2),
      intent(uuid: 'a-need', owner: 'A', direction: IntentDirection.need, axis: 2),
    ];

    test('closed 3-loop is found exactly once with a stable canonical id',
        () {
      const matcher = RingMatcher();
      final rings = matcher.findRings(corpus);
      expect(rings, hasLength(1));
      expect(rings.single.participantCount, 3);
      expect(rings.single.canonicalId, 'a-off>b-off>c-off');
      expect(rings.single.minSimilarity, closeTo(1.0, 1e-9));
    });

    test('output is invariant under input permutation', () {
      const matcher = RingMatcher();
      final baseline = matcher.findRings(corpus);
      final permutations = [
        corpus.reversed.toList(),
        [corpus[3], corpus[0], corpus[5], corpus[2], corpus[1], corpus[4]],
      ];
      for (final permuted in permutations) {
        final rings = matcher.findRings(permuted);
        expect(rings.length, baseline.length);
        for (var i = 0; i < rings.length; i++) {
          expect(rings[i].canonicalId, baseline[i].canonicalId);
        }
      }
    });

    test('self-satisfaction never forms an edge', () {
      const matcher = RingMatcher();
      final selfish = [
        intent(uuid: 'x-off', owner: 'X', direction: IntentDirection.offer, axis: 0),
        intent(uuid: 'x-need', owner: 'X', direction: IntentDirection.need, axis: 0),
      ];
      expect(matcher.findRings(selfish), isEmpty);
    });

    test('BarterRing.rank is a deterministic total order', () {
      const matcher = RingMatcher();
      final rings = matcher.findRings(corpus);
      final again = matcher.findRings(List.of(corpus));
      expect(BarterRing.rank(rings.single, again.single), 0);
    });
  });

  group('materializer fold', () {
    late InMemoryMeshRepository repository;
    late CrdtMaterializer materializer;
    late Ed25519IdentitySigner owner;
    late Ed25519IdentitySigner stranger;

    Future<CrdtStateLog> op({
      required Ed25519IdentitySigner signer,
      required String opName,
      required String intentUuid,
      required int clock,
      Map<String, dynamic>? intent,
      String? txId,
    }) async {
      final payload = jsonStablePayload(
        op: opName,
        author: signer.publicKeyHex,
        intent: intent,
      );
      return CrdtStateLog(
        transactionUuid: txId ?? secureUuidV4(),
        targetIntentUuid: intentUuid,
        authoritySignature:
            await signer.signToHex(crdtSignaturePreimage(payload, clock)),
        lamportLogicalClock: clock,
        operationPayloadJson: payload,
      );
    }

    Map<String, dynamic> createBody(String uuid, String ownerKey) => {
          'intentUuid': uuid,
          'originNodeKey': ownerKey,
          'category': AllocationCategory.peerExchange.wireValue,
          'direction': IntentDirection.offer.wireValue,
          'rawText': 'dart tutoring',
          'vector': List<double>.filled(kEmbeddingDimensions, 0.0)..[0] = 1.0,
          'quantity': 1,
          'epochMs': 1000,
        };

    setUp(() async {
      repository = InMemoryMeshRepository();
      materializer = CrdtMaterializer(repository);
      owner = await Ed25519IdentitySigner.generate();
      stranger = await Ed25519IdentitySigner.generate();
    });

    test('create materializes an open row; re-fold is idempotent', () async {
      const uuid = 'intent-1';
      final create = await op(
        signer: owner,
        opName: CrdtOps.createIntent,
        intentUuid: uuid,
        clock: 1,
        intent: createBody(uuid, owner.publicKeyHex),
      );
      await repository.appendDeltas([create]);

      final first = await materializer.materializeIntent(uuid);
      expect(first.applied, 1);
      expect(first.materialized, isTrue);

      final again = await materializer.materializeIntent(uuid);
      expect(again.applied, first.applied);

      final row = await repository.findIntentByUuid(uuid);
      expect(row!.status, IntentStatus.open);
      expect(row.originNodeKey, owner.publicKeyHex);
    });

    test('fold result is arrival-order independent', () async {
      const uuid = 'intent-2';
      final create = await op(
        signer: owner,
        opName: CrdtOps.createIntent,
        intentUuid: uuid,
        clock: 1,
        intent: createBody(uuid, owner.publicKeyHex),
      );
      final lock = await op(
        signer: owner,
        opName: CrdtOps.lockIntent,
        intentUuid: uuid,
        clock: 2,
      );

      // Lock arrives BEFORE create (partition replay) — first fold rejects
      // it as rule-benign, the re-fold after create applies it.
      await repository.appendDeltas([lock]);
      await materializer.materializeIntent(uuid);
      expect(await repository.findIntentByUuid(uuid), isNull);

      await repository.appendDeltas([create]);
      await materializer.materializeIntent(uuid);
      final row = await repository.findIntentByUuid(uuid);
      expect(row!.status, IntentStatus.lockedInLoop);
    });

    test('valid signature under the wrong key is still a rejection',
        () async {
      const uuid = 'intent-3';
      await repository.appendDeltas([
        await op(
          signer: owner,
          opName: CrdtOps.createIntent,
          intentUuid: uuid,
          clock: 1,
          intent: createBody(uuid, owner.publicKeyHex),
        ),
        // Correctly signed by the stranger — authenticated, NOT authorized.
        await op(
          signer: stranger,
          opName: CrdtOps.withdrawIntent,
          intentUuid: uuid,
          clock: 2,
        ),
      ]);

      final report = await materializer.materializeIntent(uuid);
      expect(report.rejectedRule, 1);
      expect(report.rejectedSignature, 0);
      final row = await repository.findIntentByUuid(uuid);
      expect(row!.status, IntentStatus.open);
    });

    test('tampered payload fails signature verification', () async {
      const uuid = 'intent-4';
      final genuine = await op(
        signer: owner,
        opName: CrdtOps.createIntent,
        intentUuid: uuid,
        clock: 1,
        intent: createBody(uuid, owner.publicKeyHex),
      );
      final tampered = CrdtStateLog(
        transactionUuid: genuine.transactionUuid,
        targetIntentUuid: genuine.targetIntentUuid,
        authoritySignature: genuine.authoritySignature,
        lamportLogicalClock: genuine.lamportLogicalClock,
        operationPayloadJson:
            genuine.operationPayloadJson.replaceFirst('tutoring', 'tampered'),
      );
      await repository.appendDeltas([tampered]);

      final report = await materializer.materializeIntent(uuid);
      expect(report.rejectedSignature, 1);
      expect(report.materialized, isFalse);
    });

    test('satisfied is absorbing: later withdraw cannot resurrect', () async {
      const uuid = 'intent-5';
      await repository.appendDeltas([
        await op(
          signer: owner,
          opName: CrdtOps.createIntent,
          intentUuid: uuid,
          clock: 1,
          intent: createBody(uuid, owner.publicKeyHex),
        ),
        await op(
          signer: owner,
          opName: CrdtOps.satisfyIntent,
          intentUuid: uuid,
          clock: 2,
        ),
        await op(
          signer: owner,
          opName: CrdtOps.withdrawIntent,
          intentUuid: uuid,
          clock: 3,
        ),
      ]);

      final report = await materializer.materializeIntent(uuid);
      expect(report.applied, 2);
      expect(report.rejectedRule, 1);
      final row = await repository.findIntentByUuid(uuid);
      expect(row!.status, IntentStatus.satisfied);
    });
  });
}
