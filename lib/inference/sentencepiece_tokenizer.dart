// lib/inference/sentencepiece_tokenizer.dart
//
// SentencePiece **Unigram** tokenizer for XLM-R-family models
// (paraphrase-multilingual-MiniLM-L12-v2). Pure Dart, deterministic —
// the id sequence for a given string must be identical on every device
// or nodes embed the same text differently and matching diverges.
//
// Pipeline mirrors the reference tokenizer.json exactly where it
// matters, verified against transformers.js goldens in
// test/sentencepiece_test.dart:
//   WhitespaceSplit -> Metaspace('▁', prefix) -> per-word Viterbi over
//   the scored vocabulary -> <s> ids </s> framing, consecutive unknown
//   runes fused into a single <unk> (fuse_unk semantics).
//
// Documented approximation: the reference "Precompiled" normalizer
// (SentencePiece charsmap ≈ NFKC + space cleanup) is replaced by
// control-char stripping + whitespace splitting. Identity for everyday
// RU/EN text; typographic exotica may tokenize differently ON ALL
// DEVICES EQUALLY — degraded, never divergent.

import 'token_encoder.dart';

class SentencePieceUnigramTokenizer implements TokenEncoder {
  SentencePieceUnigramTokenizer(List<String> tsvLines)
      : _entries = <String, ({int id, double score})>{} {
    var id = 0;
    var minScore = 0.0;
    var maxRunes = 1;
    for (final line in tsvLines) {
      if (line.isEmpty) continue;
      final tab = line.lastIndexOf('\t');
      if (tab <= 0) continue;
      final piece = line.substring(0, tab);
      final score = double.parse(line.substring(tab + 1));
      _entries[piece] = (id: id, score: score);
      if (score < minScore) minScore = score;
      final runeCount = piece.runes.length;
      if (runeCount > maxRunes) maxRunes = runeCount;
      id += 1;
    }
    if (id < 5) {
      throw ArgumentError('Vocabulary too small: $id entries');
    }
    _maxPieceRunes = maxRunes;
    // Reference Unigram semantics: unknown characters score a fixed
    // penalty below the worst vocabulary piece.
    _unkScore = minScore - 10.0;
  }

  final Map<String, ({int id, double score})> _entries;
  late final int _maxPieceRunes;
  late final double _unkScore;

  /// XLM-R id layout (added_tokens in tokenizer.json): fixed by the
  /// model export, not configurable.
  static const int bosId = 0;
  static const int padId = 1;
  static const int eosId = 2;
  static const int unkId = 3;

  static const String _metaspace = '▁';

  int get vocabSize => _entries.length;

  @override
  List<int> encode(String text, {int maxTokens = 256}) {
    assert(maxTokens >= 2, 'need room for <s> and </s>');
    final ids = <int>[bosId];
    final budget = maxTokens - 2;

    outer:
    for (final word in _pretokenize(text)) {
      for (final id in _viterbi('$_metaspace$word')) {
        if (ids.length - 1 >= budget) break outer;
        ids.add(id);
      }
    }
    ids.add(eosId);
    return ids;
  }

  /// WhitespaceSplit + control-char hygiene (the normalizer
  /// approximation documented in the header).
  Iterable<String> _pretokenize(String text) sync* {
    final cleaned = String.fromCharCodes(
      text.runes.where((r) =>
          !(r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) &&
          r != 0xFFFD &&
          r != 0),
    );
    for (final word in cleaned.split(RegExp(r'\s+'))) {
      if (word.isNotEmpty) yield word;
    }
  }

  /// Max-sum Viterbi segmentation of one Metaspace-prefixed word.
  List<int> _viterbi(String word) {
    final runes = word.runes.toList(growable: false);
    final n = runes.length;
    final bestScore = List<double>.filled(n + 1, double.negativeInfinity);
    final prev = List<int>.filled(n + 1, -1);
    final tokenAt = List<int>.filled(n + 1, -1);
    bestScore[0] = 0.0;

    for (var end = 1; end <= n; end++) {
      final windowStart = end - _maxPieceRunes < 0 ? 0 : end - _maxPieceRunes;
      for (var start = windowStart; start < end; start++) {
        if (bestScore[start] == double.negativeInfinity) continue;
        final piece = String.fromCharCodes(runes, start, end);
        final entry = _entries[piece];
        if (entry == null) continue;
        final candidate = bestScore[start] + entry.score;
        if (candidate > bestScore[end]) {
          bestScore[end] = candidate;
          prev[end] = start;
          tokenAt[end] = entry.id;
        }
      }
      // Unknown single-rune transition — always available, always worse
      // than any real piece covering the same span.
      final viaUnk = bestScore[end - 1] + _unkScore;
      if (viaUnk > bestScore[end]) {
        bestScore[end] = viaUnk;
        prev[end] = end - 1;
        tokenAt[end] = unkId;
      }
    }

    final reversed = <int>[];
    var at = n;
    while (at > 0) {
      reversed.add(tokenAt[at]);
      at = prev[at];
    }

    // fuse_unk: consecutive unknowns collapse into one <unk>.
    final out = <int>[];
    for (final id in reversed.reversed) {
      if (id == unkId && out.isNotEmpty && out.last == unkId) continue;
      out.add(id);
    }
    return out;
  }
}
