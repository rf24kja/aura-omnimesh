// The identity primitive. Every reputation edge, every ring lock, every
// bridge handshake rests on this one contract:
//
//   * the 32-byte seed IS the whole identity (CLAUDE.md invariant 6) —
//     export it, reconstruct from it, and you get a byte-identical signer,
//     so the seed alone is a faithful, portable custody token;
//   * signatures are deterministic (invariant 3) — the same seed over the
//     same message yields identical bytes on every device;
//   * verification is the authenticity gate and fails CLOSED — a wrong key,
//     a tampered message, or structurally garbage input returns false, it
//     never throws and never accidentally passes.
//
// crdtSignaturePreimage / handshakeChallengePreimage byte layouts are
// pinned in determinism_test; this file pins the signer that consumes them.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';

Uint8List msg(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('key material shape', () {
    test('generate yields a 64-hex public key and a distinct 64-hex seed',
        () async {
      final s = await Ed25519IdentitySigner.generate();
      final seed = await s.exportSeedHex();
      expect(s.publicKeyHex, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(seed, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(seed, isNot(s.publicKeyHex),
          reason: 'the secret seed must never equal the public key');
    });

    test('two fresh identities differ (platform CSPRNG)', () async {
      final a = await Ed25519IdentitySigner.generate();
      final b = await Ed25519IdentitySigner.generate();
      expect(a.publicKeyHex, isNot(b.publicKeyHex));
    });
  });

  group('seed custody — invariant 6 (the seed is the whole identity)', () {
    test('export -> fromSeedHex reconstructs a byte-identical identity',
        () async {
      final original = await Ed25519IdentitySigner.generate();
      final seed = await original.exportSeedHex();

      final restored = await Ed25519IdentitySigner.fromSeedHex(seed);
      expect(restored.publicKeyHex, original.publicKeyHex);
      expect(await restored.exportSeedHex(), seed);

      // A signature from the RESTORED signer verifies under the ORIGINAL
      // public key — proof the seed carried the entire identity across the
      // secure-storage round trip.
      final m = msg('resume after reinstall');
      final sig = await restored.signToHex(m);
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: sig, publicKeyHex: original.publicKeyHex),
        isTrue,
      );
    });

    test('reconstruction is deterministic and so are signatures '
        '(invariant 3)', () async {
      final seed = await (await Ed25519IdentitySigner.generate()).exportSeedHex();
      final a = await Ed25519IdentitySigner.fromSeedHex(seed);
      final b = await Ed25519IdentitySigner.fromSeedHex(seed);

      expect(a.publicKeyHex, b.publicKeyHex);
      final m = msg('deterministic ed25519');
      expect(await a.signToHex(m), await b.signToHex(m),
          reason: 'RFC 8032 Ed25519 is deterministic — two devices holding '
              'the same seed must produce identical signatures');
    });

    test('fromSeedHex rejects a seed that is not exactly 32 bytes', () async {
      expect(
        () => Ed25519IdentitySigner.fromSeedHex('00' * 31),
        throwsArgumentError,
      );
      expect(
        () => Ed25519IdentitySigner.fromSeedHex('00' * 33),
        throwsArgumentError,
      );
    });

    test('fromSeedHex rejects structurally invalid hex', () async {
      expect(
        () => Ed25519IdentitySigner.fromSeedHex('xyz'),
        throwsFormatException,
      );
    });
  });

  group('sign / verify authenticity gate', () {
    test('a genuine signature verifies under its own key', () async {
      final s = await Ed25519IdentitySigner.generate();
      final m = msg('lock ring 42');
      final sig = await s.signToHex(m);
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: sig, publicKeyHex: s.publicKeyHex),
        isTrue,
      );
    });

    test('a tampered message fails verification', () async {
      final s = await Ed25519IdentitySigner.generate();
      final sig = await s.signToHex(msg('quantity: 1'));
      expect(
        await verifyEd25519Hex(
          message: msg('quantity: 9'),
          signatureHex: sig,
          publicKeyHex: s.publicKeyHex,
        ),
        isFalse,
      );
    });

    test('a signature does not verify under the WRONG key (authentication)',
        () async {
      final signer = await Ed25519IdentitySigner.generate();
      final other = await Ed25519IdentitySigner.generate();
      final m = msg('impersonation attempt');
      final sig = await signer.signToHex(m);
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: sig, publicKeyHex: other.publicKeyHex),
        isFalse,
        reason: 'only the true key holder produces a verifiable signature',
      );
    });
  });

  group('verify fails closed on garbage — one failure path, never a throw',
      () {
    late String goodPub;
    late String goodSig;
    late Uint8List m;

    setUp(() async {
      final s = await Ed25519IdentitySigner.generate();
      m = msg('canonical');
      goodSig = await s.signToHex(m);
      goodPub = s.publicKeyHex;
    });

    test('non-hex signature or key returns false', () async {
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: 'nothex!!', publicKeyHex: goodPub),
        isFalse,
      );
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: goodSig, publicKeyHex: 'zz$goodPub'),
        isFalse,
      );
    });

    test('wrong-length key or signature returns false', () async {
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: goodSig, publicKeyHex: 'ab' * 31),
        isFalse,
        reason: 'a 31-byte key is not an Ed25519 public key',
      );
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: 'cd' * 63, publicKeyHex: goodPub),
        isFalse,
        reason: 'a 63-byte signature is malformed',
      );
    });

    test('empty strings return false', () async {
      expect(
        await verifyEd25519Hex(
            message: m, signatureHex: '', publicKeyHex: ''),
        isFalse,
      );
    });
  });
}
