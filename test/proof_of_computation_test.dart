// Module B proof-of-computation primitive: the canonical result digest a
// worker signs and any peer re-derives to check correctness by re-execution
// (docs/MODULE_B_DESIGN.md §4). The digest must be DETERMINISTIC (same result
// -> same digest on every device), TOLERANT of sub-grid float jitter (so
// heterogeneous ONNX runtimes still agree), and SENSITIVE to real differences
// (a wrong or tampered result must not pass a verifier's re-check).

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/proof_of_computation.dart';

void main() {
  List<double> vec(int n, double seed) =>
      List<double>.generate(n, (i) => ((i * 7 + 3) % 100) / 100.0 * seed);

  group('canonicalEmbeddingBytes', () {
    test('length is 4 bytes per dimension', () {
      expect(canonicalEmbeddingBytes(vec(384, 1.0)).length, 384 * 4);
      expect(canonicalEmbeddingBytes(const []).length, 0);
    });

    test('jitter below the grid produces identical bytes', () {
      // decimals=3 -> grid 1e-3. 0.5001 and 0.5004 both quantize to 500.
      final a = canonicalEmbeddingBytes([0.5001, -0.2502], decimals: 3);
      final b = canonicalEmbeddingBytes([0.5004, -0.2498], decimals: 3);
      expect(a, b);
    });

    test('a change above the grid produces different bytes', () {
      final a = canonicalEmbeddingBytes([0.5001], decimals: 3);
      final b = canonicalEmbeddingBytes([0.5019], decimals: 3); // -> 502
      expect(a, isNot(b));
    });

    test('negative dimensions round-trip through two-complement LE', () {
      // -0.5 at decimals=1 -> -5 -> 0xFFFFFFFB little-endian.
      final bytes = canonicalEmbeddingBytes([-0.5], decimals: 1);
      expect(bytes, [0xFB, 0xFF, 0xFF, 0xFF]);
    });
  });

  group('computeResultDigest', () {
    final v = vec(384, 1.0);

    test('is a 64-hex SHA-256 string', () async {
      final d = await computeResultDigest(taskId: 't1', output: v);
      expect(d, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('deterministic: same task + result -> identical digest', () async {
      final a = await computeResultDigest(taskId: 't1', output: v);
      final b = await computeResultDigest(taskId: 't1', output: List.of(v));
      expect(a, b);
    });

    test('sub-grid jitter does not change the digest (cross-runtime parity)',
        () async {
      final jittered = v.map((x) => x + 0.00002).toList(); // < 0.5 * 1e-4
      final a = await computeResultDigest(taskId: 't1', output: v);
      final b = await computeResultDigest(taskId: 't1', output: jittered);
      expect(a, b);
    });

    test('a materially different result yields a different digest', () async {
      final wrong = List.of(v)..[0] = v[0] + 0.01;
      final a = await computeResultDigest(taskId: 't1', output: v);
      final b = await computeResultDigest(taskId: 't1', output: wrong);
      expect(a, isNot(b));
    });

    test('the digest binds the task id (no cross-task replay)', () async {
      final a = await computeResultDigest(taskId: 't1', output: v);
      final b = await computeResultDigest(taskId: 't2', output: v);
      expect(a, isNot(b),
          reason: 'a result for task t1 must not verify as task t2');
    });

    test('vector length is part of the digest (no truncation collision)',
        () async {
      final a = await computeResultDigest(taskId: 't1', output: v);
      final b = await computeResultDigest(
          taskId: 't1', output: v.sublist(0, v.length - 1));
      expect(a, isNot(b));
    });

    test('empty task id and empty output still hash deterministically',
        () async {
      final a = await computeResultDigest(taskId: '', output: const []);
      final b = await computeResultDigest(taskId: '', output: const []);
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
