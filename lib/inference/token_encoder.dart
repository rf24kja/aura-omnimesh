// lib/inference/token_encoder.dart
//
// Minimal contract between OnnxEmbeddingService and its tokenizers, so
// the service stays agnostic of WordPiece vs SentencePiece internals.

abstract interface class TokenEncoder {
  /// Model-ready id sequence including begin/end special tokens, hard-
  /// capped at [maxTokens] ids. Over-long input truncates, never throws.
  List<int> encode(String text, {int maxTokens});
}
