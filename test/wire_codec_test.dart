// Wire-format hardening. The transport codec parses UNTRUSTED input from
// peers (adversarial by design), so a malformed frame must throw a clean
// FormatException — never a partial object, a crash, or a smuggled value.

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/services/services.dart';
import 'package:omnimesh/transport/hybrid_transport_service.dart';

void main() {
  group('CrdtStateLog codec', () {
    final log = CrdtStateLog(
      transactionUuid: 'tx-1',
      targetIntentUuid: 'intent-1',
      authoritySignature: 'deadbeef',
      lamportLogicalClock: 7,
      operationPayloadJson: '{"op":"create_intent"}',
    );

    test('toWire -> fromWire is a faithful round trip', () {
      final wire = crdtLogToWire(log);
      final back = crdtLogFromWire(wire);
      expect(back.transactionUuid, log.transactionUuid);
      expect(back.targetIntentUuid, log.targetIntentUuid);
      expect(back.authoritySignature, log.authoritySignature);
      expect(back.lamportLogicalClock, log.lamportLogicalClock);
      expect(back.operationPayloadJson, log.operationPayloadJson);
    });

    Map<String, dynamic> validWire() => crdtLogToWire(log);

    test('rejects a missing field', () {
      for (final key in ['txId', 'target', 'sig', 'clock', 'op']) {
        final wire = validWire()..remove(key);
        expect(() => crdtLogFromWire(wire), throwsFormatException,
            reason: 'missing $key must be rejected');
      }
    });

    test('rejects a wrong-typed field', () {
      final wrongs = <String, Object?>{
        'txId': 42, // int where string expected
        'target': ['a'], // list
        'sig': null, // null
        'clock': '7', // string where int expected
        'op': 12.5, // double
      };
      wrongs.forEach((key, bad) {
        final wire = validWire()..[key] = bad;
        expect(() => crdtLogFromWire(wire), throwsFormatException,
            reason: '$key = $bad must be rejected');
      });
    });

    test('a double clock (JSON number) is rejected, not truncated', () {
      // JSON numbers can decode as double; the clock must be a true int.
      final wire = validWire()..['clock'] = 7.0;
      expect(() => crdtLogFromWire(wire), throwsFormatException);
    });

    test('extra unknown fields are ignored (forward compatible)', () {
      final wire = validWire()..['futureField'] = 'ignored';
      expect(crdtLogFromWire(wire).transactionUuid, 'tx-1');
    });
  });

  group('NodeIdentity codec', () {
    test('reliabilityScore from the wire is ALWAYS discarded to 0', () {
      // Security invariant: a hostile peer cannot inflate its own trust
      // by putting a score on the wire. Recomputed locally only.
      final node = nodeIdentityFromWire(<String, dynamic>{
        'publicKey': 'a' * 64,
        'alias': 'attacker',
        'reliabilityScore': 99,
        'trust': 100,
      });
      expect(node.reliabilityScore, 0);
      expect(node.cryptographicPublicKey, 'a' * 64);
      expect(node.localAlias, 'attacker');
    });

    test('rejects non-string key or alias', () {
      expect(
        () => nodeIdentityFromWire({'publicKey': 123, 'alias': 'x'}),
        throwsFormatException,
      );
      expect(
        () => nodeIdentityFromWire({'publicKey': 'x', 'alias': null}),
        throwsFormatException,
      );
      expect(
        () => nodeIdentityFromWire(const <String, dynamic>{}),
        throwsFormatException,
      );
    });
  });

  group('MeshNodeState codec', () {
    test('every valid wire value maps', () {
      expect(meshNodeStateFromWire('discovered'), MeshNodeState.discovered);
      expect(meshNodeStateFromWire('connecting'), MeshNodeState.connecting);
      expect(meshNodeStateFromWire('connected'), MeshNodeState.connected);
      expect(meshNodeStateFromWire('degraded'), MeshNodeState.degraded);
      expect(meshNodeStateFromWire('lost'), MeshNodeState.lost);
    });

    test('unknown / empty / cased values are rejected', () {
      for (final bad in ['', 'CONNECTED', 'online', 'x']) {
        expect(() => meshNodeStateFromWire(bad), throwsFormatException,
            reason: '"$bad" must be rejected');
      }
    });
  });
}
