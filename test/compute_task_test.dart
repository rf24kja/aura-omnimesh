// Module B compute-task fold: the state machine + authorization that mirrors
// the intent materializer but with WORKER-authored transitions. This locks
// the genuinely new rule — claim/result are authored by the worker, not the
// task owner — while still rejecting a valid signature under a key not
// entitled to that transition (auth != authz, invariant 7).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/compute_task.dart';
import 'package:omnimesh/compute/proof_of_computation.dart';
import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';

void main() {
  late Ed25519IdentitySigner requester;
  late Ed25519IdentitySigner worker;
  late Ed25519IdentitySigner attacker;

  setUp(() async {
    requester = await Ed25519IdentitySigner.generate();
    worker = await Ed25519IdentitySigner.generate();
    attacker = await Ed25519IdentitySigner.generate();
  });

  Future<CrdtStateLog> op(
    Ed25519IdentitySigner by,
    String taskUuid,
    Map<String, dynamic> map,
    int clock,
  ) async {
    final payload = jsonEncode(map);
    return CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: taskUuid,
      authoritySignature:
          await by.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    );
  }

  Future<CrdtStateLog> offer(String uuid, {int clock = 1}) => op(
        requester,
        uuid,
        computeOfferPayload(
          taskUuid: uuid,
          requesterKey: requester.publicKeyHex,
          inputText: 'embed: нужна помощь с переездом',
          epochMs: 1000,
        ),
        clock,
      );

  group('lifecycle', () {
    test('offer -> claim -> result reaches completed with the digest',
        () async {
      const uuid = 'task-1';
      final digest = await computeResultDigest(
        taskId: uuid,
        output: List<double>.filled(384, 0.01),
      );
      final log = [
        await offer(uuid),
        await op(worker, uuid,
            computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
            2),
        await op(
            worker,
            uuid,
            computeResultPayload(
                taskUuid: uuid,
                workerKey: worker.publicKeyHex,
                outputDigest: digest),
            3),
      ];
      final f = await foldComputeTask(log);
      expect(f.rejectedSignature, 0);
      expect(f.rejectedRule, 0);
      expect(f.state!.status, ComputeTaskStatus.completed);
      expect(f.state!.claimedByKey, worker.publicKeyHex);
      expect(f.state!.resultDigest, digest);
    });

    test('fold is arrival-order independent (sorted by causalCompare)',
        () async {
      const uuid = 'task-2';
      final o = await offer(uuid, clock: 1);
      final c = await op(worker, uuid,
          computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
          2);
      final forward = await foldComputeTask([o, c]);
      final reversed = await foldComputeTask([c, o]);
      expect(forward.state!.status, ComputeTaskStatus.claimed);
      expect(reversed.state!.status, ComputeTaskStatus.claimed);
    });
  });

  group('authorization (auth != authz)', () {
    test('only the claiming worker may post the result', () async {
      const uuid = 'task-3';
      final digest = await computeResultDigest(
          taskId: uuid, output: List<double>.filled(384, 0.02));
      final log = [
        await offer(uuid),
        await op(worker, uuid,
            computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
            2),
        // Attacker signs a perfectly valid result with ITS OWN key.
        await op(
            attacker,
            uuid,
            computeResultPayload(
                taskUuid: uuid,
                workerKey: attacker.publicKeyHex,
                outputDigest: digest),
            3),
      ];
      final f = await foldComputeTask(log);
      expect(f.rejectedSignature, 0,
          reason: 'the attacker signature is valid — not an auth failure');
      expect(f.rejectedRule, greaterThanOrEqualTo(1));
      expect(f.state!.status, ComputeTaskStatus.claimed,
          reason: 'a non-claimer must not complete the task');
    });

    test('only the requester may withdraw its task', () async {
      const uuid = 'task-4';
      final log = [
        await offer(uuid),
        // Worker (not the requester) tries to withdraw.
        await op(worker, uuid,
            computeWithdrawPayload(
                taskUuid: uuid, requesterKey: worker.publicKeyHex),
            2),
      ];
      final f = await foldComputeTask(log);
      expect(f.rejectedRule, greaterThanOrEqualTo(1));
      expect(f.state!.status, ComputeTaskStatus.offered);
    });

    test('any worker may claim an offered task', () async {
      const uuid = 'task-5';
      final f = await foldComputeTask([
        await offer(uuid),
        await op(worker, uuid,
            computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
            2),
      ]);
      expect(f.rejectedRule, 0);
      expect(f.state!.status, ComputeTaskStatus.claimed);
    });
  });

  group('state machine rules', () {
    test('claim before offer no-ops, then converges on the offer', () async {
      const uuid = 'task-6';
      final claimEarly = await op(worker, uuid,
          computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
          1);
      // Only the claim, no offer: nothing to claim.
      final r1 = await foldComputeTask([claimEarly]);
      expect(r1.state, isNull);
      expect(r1.rejectedRule, greaterThanOrEqualTo(1));

      // With the offer at a LATER clock, causalCompare still orders offer
      // (clock 2) after the claim (clock 1) — so the claim is folded first
      // (no state) and rejected; the offer then creates the state. This
      // documents that a worker must not claim before seeing the offer.
      final offerLater = await offer(uuid, clock: 2);
      final r2 = await foldComputeTask([claimEarly, offerLater]);
      expect(r2.state!.status, ComputeTaskStatus.offered);
    });

    test('completed is absorbing: a later withdraw cannot retract it',
        () async {
      const uuid = 'task-7';
      final digest = await computeResultDigest(
          taskId: uuid, output: List<double>.filled(384, 0.03));
      final f = await foldComputeTask([
        await offer(uuid),
        await op(worker, uuid,
            computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
            2),
        await op(
            worker,
            uuid,
            computeResultPayload(
                taskUuid: uuid,
                workerKey: worker.publicKeyHex,
                outputDigest: digest),
            3),
        await op(requester, uuid,
            computeWithdrawPayload(
                taskUuid: uuid, requesterKey: requester.publicKeyHex),
            4),
      ]);
      expect(f.state!.status, ComputeTaskStatus.completed);
      expect(f.rejectedRule, greaterThanOrEqualTo(1));
    });

    test('a claimed task cannot be claimed again', () async {
      const uuid = 'task-8';
      final f = await foldComputeTask([
        await offer(uuid),
        await op(worker, uuid,
            computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
            2),
        await op(attacker, uuid,
            computeClaimPayload(
                taskUuid: uuid, workerKey: attacker.publicKeyHex),
            3),
      ]);
      expect(f.state!.claimedByKey, worker.publicKeyHex);
      expect(f.rejectedRule, greaterThanOrEqualTo(1));
    });

    test('a result with an empty digest is rejected', () async {
      const uuid = 'task-9';
      final f = await foldComputeTask([
        await offer(uuid),
        await op(worker, uuid,
            computeClaimPayload(taskUuid: uuid, workerKey: worker.publicKeyHex),
            2),
        await op(
            worker,
            uuid,
            computeResultPayload(
                taskUuid: uuid, workerKey: worker.publicKeyHex, outputDigest: ''),
            3),
      ]);
      expect(f.state!.status, ComputeTaskStatus.claimed);
      expect(f.rejectedRule, greaterThanOrEqualTo(1));
    });
  });

  group('construction + authentication', () {
    test('offer whose task.requesterKey != the signing author is rejected',
        () async {
      const uuid = 'task-10';
      // Author == the signer (so the signature verifies), but the task body
      // names a DIFFERENT requester — the binding invariant forbids it.
      final bad = await op(requester, uuid, <String, dynamic>{
        'op': ComputeOps.offer,
        'author': requester.publicKeyHex,
        'task': <String, dynamic>{
          'taskUuid': uuid,
          'requesterKey': attacker.publicKeyHex,
          'inputText': 'x',
          'epochMs': 1,
        },
      }, 1);
      final f = await foldComputeTask([bad]);
      expect(f.rejectedSignature, 0);
      expect(f.state, isNull);
      expect(f.rejectedRule, 1);
    });

    test('offer whose taskUuid mismatches the target is rejected', () async {
      final bad = await op(
          requester,
          'target-uuid',
          computeOfferPayload(
              taskUuid: 'other-uuid',
              requesterKey: requester.publicKeyHex,
              inputText: 'x',
              epochMs: 1),
          1);
      final f = await foldComputeTask([bad]);
      expect(f.state, isNull);
      expect(f.rejectedRule, 1);
    });

    test('a tampered payload fails signature verification', () async {
      const uuid = 'task-11';
      final good = await offer(uuid);
      final tampered = CrdtStateLog(
        transactionUuid: good.transactionUuid,
        targetIntentUuid: good.targetIntentUuid,
        authoritySignature: good.authoritySignature,
        lamportLogicalClock: good.lamportLogicalClock,
        operationPayloadJson:
            good.operationPayloadJson.replaceFirst('переездом', 'HACKED'),
      );
      final f = await foldComputeTask([tampered]);
      expect(f.rejectedSignature, 1);
      expect(f.state, isNull);
    });
  });
}
