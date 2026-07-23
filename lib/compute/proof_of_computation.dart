// lib/compute/proof_of_computation.dart
//
// Module B (SwarmCompute) proof-of-computation. See docs/MODULE_B_DESIGN.md §4.
//
// A worker signs the SHA-256 digest of its result; a compute_task_result CRDT
// op carries that digest and is Ed25519-signed through the SINGLE existing
// crdtSignaturePreimage source (invariant 1) — this file adds NO second
// signing scheme. It only produces the canonical digest that a result op
// carries and that any peer re-derives to check correctness by re-execution
// (determinism, invariant 3).
//
// Canonicalization is deliberate: a raw float32 embedding is not bit-identical
// across heterogeneous ONNX runtimes (native ARM vs web wasm agree only to
// ~1e-3), so each dimension is quantized to a fixed decimal grid before
// hashing. Same-runtime results (the common Android↔Android case) are exact;
// cross-runtime verification holds as long as parity is finer than the grid.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/ed25519_signer.dart' show encodeHex;

/// Proof precision: result dimensions are quantized to this many decimals
/// before hashing. The grid (10^-decimals) is the runtime-jitter tolerance.
const int kProofDecimals = 4;

/// Canonical, cross-device byte form of an embedding result: each dimension
/// quantized to a fixed decimal grid and serialized as a signed 32-bit
/// little-endian integer. Manual LE loop — ByteData.setInt64 throws under
/// dart2js (invariant 8). Order is preserved; the length is implicit in the
/// output size, so a truncated vector yields a different digest.
Uint8List canonicalEmbeddingBytes(
  List<double> vector, {
  int decimals = kProofDecimals,
}) {
  final scale = _pow10(decimals);
  final out = Uint8List(vector.length * 4);
  var o = 0;
  for (final v in vector) {
    // double.round() rounds halves away from zero identically on the VM and
    // under dart2js — the property the cross-device digest depends on.
    var q = (v * scale).round();
    if (q > 0x7fffffff) q = 0x7fffffff;
    if (q < -0x80000000) q = -0x80000000;
    var u = q & 0xffffffff; // two's-complement low 32 bits
    for (var i = 0; i < 4; i++) {
      out[o++] = u & 0xff;
      u >>= 8;
    }
  }
  return out;
}

/// SHA-256 hex of [bytes].
Future<String> sha256Hex(Uint8List bytes) async {
  final hash = await Sha256().hash(bytes);
  return encodeHex(Uint8List.fromList(hash.bytes));
}

/// The result digest a worker signs and a verifier re-derives:
///   SHA-256( utf8(taskId) || 0x00 || canonicalEmbeddingBytes(output) )
/// The 0x00 domain-separates the task id from the vector bytes so no taskId /
/// vector pair can collide with another by shifting the boundary.
Future<String> computeResultDigest({
  required String taskId,
  required List<double> output,
  int decimals = kProofDecimals,
}) {
  final id = utf8.encode(taskId);
  final vec = canonicalEmbeddingBytes(output, decimals: decimals);
  final preimage = Uint8List(id.length + 1 + vec.length);
  preimage.setRange(0, id.length, id);
  preimage[id.length] = 0x00;
  preimage.setRange(id.length + 1, preimage.length, vec);
  return sha256Hex(preimage);
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
