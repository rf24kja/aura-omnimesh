// CrdtMaterializer is the security core: the SOLE writer of intent rows
// (CLAUDE.md invariant 2) and the enforcement point for both
// authentication (Ed25519 signature) and authorization (invariant 7 —
// "a valid signature under the WRONG key is still a rejection"). The ring
// lifecycle test proves the happy path applies cleanly; this test proves
// the REJECTION paths hold, because a materializer that folds a hostile
// op writes that corruption into every device's view of the mesh.
//
// Assertions read the typed MaterializationReport so the distinction that
// matters is explicit: a failed signature is `rejectedSignature`; a valid
// signature doing something it isn't allowed to is `rejectedRule`. The
// two must never be conflated.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/main.dart' show InMemoryMeshRepository;

void main() {
  late InMemoryMeshRepository repo;
  late CrdtMaterializer materializer;
  late Ed25519IdentitySigner owner;
  late Ed25519IdentitySigner attacker;

  setUp(() async {
    repo = InMemoryMeshRepository();
    materializer = CrdtMaterializer(repo);
    owner = await Ed25519IdentitySigner.generate();
    attacker = await Ed25519IdentitySigner.generate();
  });

  /// Signs [map] under [by] over the canonical preimage and returns a log
  /// whose stored JSON is exactly what was signed — the materializer
  /// recomputes the preimage from that same JSON, so any later mutation of
  /// the stored JSON invalidates the signature (that's the tamper test).
  Future<CrdtStateLog> op(
    Ed25519IdentitySigner by,
    String targetUuid,
    Map<String, dynamic> map,
    int clock,
  ) async {
    final payload = jsonEncode(map);
    return CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: targetUuid,
      authoritySignature:
          await by.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    );
  }

  Map<String, dynamic> createMap(
    String uuid,
    String authorKey, {
    String? originKey,
    int axis = 0,
    IntentDirection dir = IntentDirection.offer,
    Map<String, dynamic> extraIntentFields = const {},
    int vectorLen = kEmbeddingDimensions,
  }) {
    final vector = List<double>.filled(vectorLen, 0.0);
    if (axis < vectorLen) vector[axis] = 1.0;
    return {
      'op': CrdtOps.createIntent,
      'author': authorKey,
      'intent': {
        'intentUuid': uuid,
        'originNodeKey': originKey ?? authorKey,
        'category': 'peer_exchange',
        'direction': dir.wireValue,
        'rawText': '$uuid text',
        'vector': vector,
        'quantity': 1,
        'epochMs': 1000,
        ...extraIntentFields,
      },
    };
  }

  Map<String, dynamic> transitionMap(
    String opName,
    String uuid,
    String authorKey,
  ) =>
      {'op': opName, 'intentUuid': uuid, 'author': authorKey};

  Future<MaterializationReport> fold(String uuid, List<CrdtStateLog> ops) async {
    await repo.appendDeltas(ops);
    return materializer.materializeIntent(uuid);
  }

  group('authentication — signature verification', () {
    test('a well-formed create by its origin materializes cleanly', () async {
      const uuid = 'i1';
      final report =
          await fold(uuid, [await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1)]);
      expect(report.materialized, isTrue);
      expect(report.applied, 1);
      expect(report.rejectedSignature, 0);
      expect(report.rejectedRule, 0);
      expect((await repo.findIntentByUuid(uuid))!.status, IntentStatus.open);
    });

    test('a tampered payload fails the signature, is never applied', () async {
      const uuid = 'i2';
      final good = await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1);
      // Flip the raw text AFTER signing: the stored JSON no longer matches
      // the signed preimage.
      final tampered = CrdtStateLog(
        transactionUuid: good.transactionUuid,
        targetIntentUuid: good.targetIntentUuid,
        authoritySignature: good.authoritySignature,
        lamportLogicalClock: good.lamportLogicalClock,
        operationPayloadJson:
            good.operationPayloadJson.replaceFirst('i2 text', 'i2 HACKED'),
      );
      final report = await fold(uuid, [tampered]);
      expect(report.rejectedSignature, 1);
      expect(report.applied, 0);
      expect(report.materialized, isFalse);
      expect(await repo.findIntentByUuid(uuid), isNull);
    });

    test('impersonation — signed by attacker but claims owner as author',
        () async {
      const uuid = 'i3';
      // Payload names owner as author; signature is the attacker's. The
      // materializer verifies the signature AGAINST the claimed author key,
      // so this fails authentication outright.
      final forged =
          await op(attacker, uuid, createMap(uuid, owner.publicKeyHex), 1);
      final report = await fold(uuid, [forged]);
      expect(report.rejectedSignature, 1);
      expect(report.materialized, isFalse);
    });

    test('a known-bad tx is counted once across re-folds (cache holds)',
        () async {
      const uuid = 'i4';
      final forged =
          await op(attacker, uuid, createMap(uuid, owner.publicKeyHex), 1);
      await fold(uuid, [forged]);
      await materializer.materializeIntent(uuid); // re-fold
      await materializer.materializeIntent(uuid); // re-fold again
      expect(materializer.totalRejectedSignatures, 1,
          reason: 'the rejected-tx cache must absorb re-fold repeats');
    });
  });

  group('authorization — invariant 7 (auth is not authz)', () {
    test('attacker cannot lock an intent it does not own, even with a '
        'perfectly valid signature of its own', () async {
      const uuid = 'i5';
      final create =
          await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1);
      // Attacker signs a lock op correctly WITH ITS OWN KEY. Authentication
      // passes; authorization must not.
      final hostileLock = await op(
        attacker,
        uuid,
        transitionMap('lock_intent', uuid, attacker.publicKeyHex),
        2,
      );
      final report = await fold(uuid, [create, hostileLock]);

      expect(report.rejectedSignature, 0,
          reason: 'the attacker signature IS valid — this is not an '
              'authentication failure');
      expect(report.rejectedRule, greaterThanOrEqualTo(1),
          reason: 'wrong author for a status transition is a rule rejection');
      expect((await repo.findIntentByUuid(uuid))!.status, IntentStatus.open,
          reason: 'a non-owner must never move another node\'s intent');
    });

    test('the true owner CAN lock its own intent', () async {
      const uuid = 'i6';
      final create =
          await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1);
      final lock = await op(
        owner,
        uuid,
        transitionMap('lock_intent', uuid, owner.publicKeyHex),
        2,
      );
      final report = await fold(uuid, [create, lock]);
      expect(report.rejectedRule, 0);
      expect((await repo.findIntentByUuid(uuid))!.status,
          IntentStatus.lockedInLoop);
    });
  });

  group('state-machine rules', () {
    test('absorbing state — nothing transitions out of satisfied', () async {
      const uuid = 'i7';
      final ops = [
        await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1),
        await op(owner, uuid,
            transitionMap('satisfy_intent', uuid, owner.publicKeyHex), 2),
        // Owner tries to re-lock a completed exchange — a stale fork must
        // not resurrect it.
        await op(owner, uuid,
            transitionMap('lock_intent', uuid, owner.publicKeyHex), 3),
      ];
      final report = await fold(uuid, ops);
      expect(report.rejectedRule, greaterThanOrEqualTo(1));
      expect((await repo.findIntentByUuid(uuid))!.status,
          IntentStatus.satisfied);
    });

    test('out-of-order — a lock before its create no-ops, then converges '
        'on the re-fold when the create arrives', () async {
      const uuid = 'i8';
      final create =
          await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1);
      final lock = await op(
        owner,
        uuid,
        transitionMap('lock_intent', uuid, owner.publicKeyHex),
        2,
      );

      // Lock arrives first, alone.
      final r1 = await fold(uuid, [lock]);
      expect(r1.materialized, isFalse,
          reason: 'no create yet — nothing to write');
      expect(r1.rejectedRule, greaterThanOrEqualTo(1));

      // Create arrives; the FULL causal log is re-folded in Lamport order,
      // so the lock now applies.
      final r2 = await fold(uuid, [create]);
      expect(r2.materialized, isTrue);
      expect((await repo.findIntentByUuid(uuid))!.status,
          IntentStatus.lockedInLoop);
    });

    test('unknown op from a newer protocol version is ignored, not guessed',
        () async {
      const uuid = 'i9';
      final ops = [
        await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1),
        await op(owner, uuid,
            transitionMap('teleport_intent', uuid, owner.publicKeyHex), 2),
      ];
      final report = await fold(uuid, ops);
      expect(report.rejectedRule, greaterThanOrEqualTo(1));
      expect((await repo.findIntentByUuid(uuid))!.status, IntentStatus.open);
    });
  });

  group('construction strictness — malformed remote data', () {
    test('create where originNodeKey != author is rejected', () async {
      const uuid = 'i10';
      // Author signs correctly, but claims a different origin inside the
      // intent body — the binding invariant forbids it.
      final bad = await op(
        owner,
        uuid,
        createMap(uuid, owner.publicKeyHex, originKey: attacker.publicKeyHex),
        1,
      );
      final report = await fold(uuid, [bad]);
      expect(report.rejectedSignature, 0);
      expect(report.rejectedRule, 1);
      expect(await repo.findIntentByUuid(uuid), isNull);
    });

    test('create whose intentUuid does not match the target is rejected',
        () async {
      const target = 'i11';
      final bad = await op(
        owner,
        target,
        createMap('a-different-uuid', owner.publicKeyHex),
        1,
      );
      final report = await fold(target, [bad]);
      expect(report.rejectedRule, 1);
      expect(await repo.findIntentByUuid(target), isNull);
    });

    test('create with a wrong-length vector is rejected', () async {
      const uuid = 'i12';
      final bad = await op(
        owner,
        uuid,
        createMap(uuid, owner.publicKeyHex, vectorLen: kEmbeddingDimensions - 1),
        1,
      );
      final report = await fold(uuid, [bad]);
      expect(report.rejectedRule, 1);
      expect(await repo.findIntentByUuid(uuid), isNull);
    });

    test('status is NEVER smuggled in via the create payload — intents are '
        'born open (invariant 2)', () async {
      const uuid = 'i13';
      final smuggled = await op(
        owner,
        uuid,
        createMap(uuid, owner.publicKeyHex,
            extraIntentFields: {'status': 'satisfied'}),
        1,
      );
      final report = await fold(uuid, [smuggled]);
      expect(report.materialized, isTrue);
      expect((await repo.findIntentByUuid(uuid))!.status, IntentStatus.open,
          reason: 'a create must not bypass the signed-transition rules');
    });

    test('duplicate create — first in causal order wins deterministically',
        () async {
      const uuid = 'i14';
      final first = await op(owner, uuid,
          createMap(uuid, owner.publicKeyHex, extraIntentFields: {'rawText': 'FIRST'}), 1);
      final second = await op(owner, uuid,
          createMap(uuid, owner.publicKeyHex, extraIntentFields: {'rawText': 'SECOND'}), 2);
      final report = await fold(uuid, [first, second]);
      expect(report.applied, 1, reason: 'only the causally-first create wins');
      expect(report.rejectedRule, greaterThanOrEqualTo(1));
      expect((await repo.findIntentByUuid(uuid))!.rawTextPayload, 'FIRST');
    });
  });

  test('re-folding a fixed log is idempotent — same materialized state',
      () async {
    const uuid = 'i15';
    final ops = [
      await op(owner, uuid, createMap(uuid, owner.publicKeyHex), 1),
      await op(owner, uuid,
          transitionMap('lock_intent', uuid, owner.publicKeyHex), 2),
    ];
    await fold(uuid, ops);
    final firstStatus = (await repo.findIntentByUuid(uuid))!.status;
    await materializer.materializeIntent(uuid);
    await materializer.materializeIntent(uuid);
    final afterRefolds = (await repo.findIntentByUuid(uuid))!.status;
    expect(afterRefolds, firstStatus);
    expect(afterRefolds, IntentStatus.lockedInLoop);
  });
}
