// Pure math of the MiniLM pipeline tail: mean pooling + L2 normalization.
// The ONNX runtime itself needs a device (plugin channels) — covered by
// the on-device E2E; this pins the part that must be deterministic.

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/inference/onnx_embedding_service.dart';

void main() {
  test('mean pooling averages the sequence axis and L2-normalizes', () {
    // seq=2, dims=3: token0 = (1,2,2), token1 = (3,2,0) -> mean (2,2,1),
    // norm 3 -> (2/3, 2/3, 1/3).
    final out = OnnxEmbeddingService.meanPoolAndNormalize(
      [1, 2, 2, 3, 2, 0],
      seqLength: 2,
      dims: 3,
    );
    expect(out[0], closeTo(2 / 3, 1e-12));
    expect(out[1], closeTo(2 / 3, 1e-12));
    expect(out[2], closeTo(1 / 3, 1e-12));
  });

  test('output is unit-length for arbitrary input', () {
    final out = OnnxEmbeddingService.meanPoolAndNormalize(
      List.generate(4 * 8, (i) => (i % 7) - 3),
      seqLength: 4,
      dims: 8,
    );
    var norm = 0.0;
    for (final x in out) {
      norm += x * x;
    }
    expect(norm, closeTo(1.0, 1e-9));
  });

  test('zero hidden state degrades to the fixed unit vector, never NaN',
      () {
    final out = OnnxEmbeddingService.meanPoolAndNormalize(
      List.filled(6, 0),
      seqLength: 2,
      dims: 3,
    );
    expect(out, [1.0, 0.0, 0.0]);
  });

  test('shape mismatch is an error, not silent garbage', () {
    expect(
      () => OnnxEmbeddingService.meanPoolAndNormalize(
        [1, 2, 3],
        seqLength: 2,
        dims: 3,
      ),
      throwsArgumentError,
    );
  });
}
