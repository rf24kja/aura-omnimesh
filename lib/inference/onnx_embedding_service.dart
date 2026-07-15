// lib/inference/onnx_embedding_service.dart
//
// Phase 2: production embeddings. all-MiniLM-L6-v2 (int8-quantized ONNX,
// bundled asset) behind the EdgeInferenceService contract — nothing above
// this layer changes when the FNV surrogate is swapped out, exactly as
// the architecture planned.
//
// Pipeline per sentence-transformers: WordPiece ids -> transformer ->
// mean pooling over the attention mask -> L2 normalization (dot product
// == cosine on the hot path, per the interface contract).
//
// Native targets only: the composition root keeps web Light Clients on
// the FNV fallback until the wasm execution provider is validated.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../domain/domain_models.dart';
import '../services/services.dart';
import 'wordpiece_tokenizer.dart';

class OnnxEmbeddingService implements EdgeInferenceService {
  OnnxEmbeddingService({
    this.modelAsset = 'assets/models/minilm_l6_v2_quantized.onnx',
    this.vocabAsset = 'assets/models/vocab.txt',
    this.maxTokens = 256,
  });

  final String modelAsset;
  final String vocabAsset;

  /// Context window incl. [CLS]/[SEP]; longer input is truncated by the
  /// tokenizer, never an error (interface contract).
  final int maxTokens;

  OrtSession? _session;
  WordPieceTokenizer? _tokenizer;
  List<String> _inputNames = const [];

  @override
  Future<void> warmUp() async {
    if (_session != null) return; // Safe to call repeatedly.

    _tokenizer = WordPieceTokenizer(
      (await rootBundle.loadString(vocabAsset)).split('\n'),
    );
    final session =
        await OnnxRuntime().createSessionFromAsset(modelAsset);
    _session = session;
    try {
      _inputNames = session.inputNames;
    } on Object {
      _inputNames = const []; // Older platforms: assume the BERT trio.
    }

    // One throwaway inference: graph initialization and allocator setup
    // happen here instead of inside the first user-visible match.
    await generateEmbedding('warm up');
  }

  @override
  InferenceAccelerator get activeAccelerator =>
      // CPU EP is what we configure today; NNAPI/CoreML tuning is a
      // follow-up. Honest reporting beats optimistic labels.
      InferenceAccelerator.cpuFallback;

  @override
  Future<List<double>> generateEmbedding(String input) async {
    final session = _session;
    final tokenizer = _tokenizer;
    if (session == null || tokenizer == null) {
      throw StateError('generateEmbedding called before warmUp()');
    }

    final ids = tokenizer.encode(input, maxTokens: maxTokens);
    final length = ids.length;
    final shape = [1, length];

    final inputs = <String, OrtValue>{
      'input_ids':
          await OrtValue.fromList(Int64List.fromList(ids), shape),
      'attention_mask': await OrtValue.fromList(
          Int64List.fromList(List.filled(length, 1)), shape),
      'token_type_ids': await OrtValue.fromList(
          Int64List.fromList(List.filled(length, 0)), shape),
    };
    // Models exported without token_type_ids reject unknown inputs —
    // trim to the session's declared names when the platform exposes them.
    if (_inputNames.isNotEmpty) {
      inputs.removeWhere((name, _) => !_inputNames.contains(name));
    }

    final outputs = await session.run(inputs);
    try {
      final hidden =
          outputs['last_hidden_state'] ?? outputs.values.first;
      final flat = (await hidden.asFlattenedList()).cast<num>();
      return meanPoolAndNormalize(
        flat,
        seqLength: length,
        dims: kEmbeddingDimensions,
      );
    } finally {
      for (final tensor in inputs.values) {
        await tensor.dispose();
      }
      for (final tensor in outputs.values) {
        await tensor.dispose();
      }
    }
  }

  /// Mean pooling over the sequence axis followed by L2 normalization.
  /// Pure and static so the math is unit-testable without a runtime.
  /// All tokens carry attention weight 1 here — this service never pads.
  static List<double> meanPoolAndNormalize(
    List<num> flatHiddenState, {
    required int seqLength,
    required int dims,
  }) {
    if (flatHiddenState.length != seqLength * dims) {
      throw ArgumentError(
        'Hidden state length ${flatHiddenState.length} != '
        '$seqLength x $dims',
      );
    }
    final pooled = List<double>.filled(dims, 0.0);
    for (var t = 0; t < seqLength; t++) {
      final base = t * dims;
      for (var d = 0; d < dims; d++) {
        pooled[d] += flatHiddenState[base + d].toDouble();
      }
    }
    var norm = 0.0;
    for (var d = 0; d < dims; d++) {
      pooled[d] /= seqLength;
      norm += pooled[d] * pooled[d];
    }
    if (norm == 0.0) {
      // Degenerate output (should not happen with a real model) — fixed
      // unit vector, deterministic, never NaN. Mirrors the FNV fallback.
      pooled[0] = 1.0;
      return pooled;
    }
    final inv = 1.0 / _sqrt(norm);
    for (var d = 0; d < dims; d++) {
      pooled[d] *= inv;
    }
    return pooled;
  }

  static double _sqrt(double x) {
    var guess = x / 2;
    for (var i = 0; i < 24; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  @override
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _tokenizer = null;
  }
}
