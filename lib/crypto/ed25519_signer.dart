// lib/crypto/ed25519_signer.dart
//
// Production IdentitySigner over package:cryptography, plus the CANONICAL
// crypto helpers for the CRDT operation format. Every module that signs or
// verifies operations imports the preimage function from HERE — a second
// definition drifting by one byte would silently invalidate every
// signature on the mesh.
//
// pubspec.yaml (already present from the transport layer):
//   dependencies:
//     cryptography: ^2.7.0

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../services/services.dart';

// ---------------------------------------------------------------------------
// Canonical encoding helpers
// ---------------------------------------------------------------------------

String encodeHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List decodeHex(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    throw FormatException('Invalid hex string (length ${hex.length})');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// RFC 4122 v4 UUID from the platform CSPRNG.
String secureUuidV4() {
  final rng = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(16, (_) => rng.nextInt(256), growable: false),
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = encodeHex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// Canonical CrdtStateLog signature preimage:
///   utf8(operationPayloadJson) || lamportLogicalClock as 8 LE bytes.
/// Manual little-endian loop — ByteData.setInt64 throws UnsupportedError
/// under dart2js; Lamport clocks stay far below 2^53 so bit ops are safe
/// on the web number model.
Uint8List crdtSignaturePreimage(String operationPayloadJson, int clock) {
  final payload = utf8.encode(operationPayloadJson);
  final out = Uint8List(payload.length + 8);
  out.setRange(0, payload.length, payload);
  var v = clock;
  for (var i = 0; i < 8; i++) {
    out[payload.length + i] = v & 0xff;
    v = v >> 8;
  }
  return out;
}

/// Canonical verification for hex-encoded key/signature material. Returns
/// false (never throws) on structurally invalid input — callers get
/// exactly one failure path.
Future<bool> verifyEd25519Hex({
  required Uint8List message,
  required String signatureHex,
  required String publicKeyHex,
}) async {
  final Uint8List signature;
  final Uint8List publicKey;
  try {
    signature = decodeHex(signatureHex);
    publicKey = decodeHex(publicKeyHex);
  } on FormatException {
    return false;
  }
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

// ---------------------------------------------------------------------------
// Signer
// ---------------------------------------------------------------------------

class Ed25519IdentitySigner implements IdentitySigner {
  Ed25519IdentitySigner._(this._keyPair, this.publicKeyHex);

  final SimpleKeyPair _keyPair;

  @override
  final String publicKeyHex;

  /// Fresh keypair from the platform CSPRNG. The caller MUST persist
  /// [exportSeedHex] into platform secure storage immediately, or the
  /// identity — and every reputation edge attached to it — dies with the
  /// process.
  static Future<Ed25519IdentitySigner> generate() async {
    final keyPair = await Ed25519().newKeyPair();
    return _fromKeyPair(keyPair);
  }

  /// Deterministic reconstruction from a stored 32-byte seed.
  static Future<Ed25519IdentitySigner> fromSeedHex(String seedHex) async {
    final seed = decodeHex(seedHex);
    if (seed.length != 32) {
      throw ArgumentError.value(
        seedHex.length,
        'seedHex',
        'Ed25519 seed must be exactly 32 bytes (64 hex chars)',
      );
    }
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    return _fromKeyPair(keyPair);
  }

  static Future<Ed25519IdentitySigner> _fromKeyPair(
    SimpleKeyPair keyPair,
  ) async {
    final publicKey = await keyPair.extractPublicKey();
    return Ed25519IdentitySigner._(
      keyPair,
      encodeHex(Uint8List.fromList(publicKey.bytes)),
    );
  }

  /// Exports the private seed for persistence. Storage contract: platform
  /// secure enclave-backed storage ONLY (Keychain / Android Keystore via
  /// flutter_secure_storage). Never SharedPreferences, never a plain file,
  /// never logs.
  Future<String> exportSeedHex() async {
    final bytes = await _keyPair.extractPrivateKeyBytes();
    return encodeHex(Uint8List.fromList(bytes));
  }

  @override
  Future<String> signToHex(Uint8List message) async {
    final signature = await Ed25519().sign(message, keyPair: _keyPair);
    return encodeHex(Uint8List.fromList(signature.bytes));
  }
}
