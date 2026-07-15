// lib/inference/wordpiece_tokenizer.dart
//
// Phase 2 groundwork: pure-Dart BERT-uncased tokenizer (basic tokenizer +
// greedy WordPiece) for all-MiniLM-L6-v2. Zero dependencies and fully
// deterministic — the token id sequence for a given string must be
// identical on every device, or two nodes embed the same text differently
// and matching diverges (the same invariant the FNV fallback honors).
//
// Deliberate approximations, documented:
//  - Accent folding uses a compact Latin fold table instead of full NFD
//    (Dart has no built-in Unicode normalization). Uncovered accented
//    forms degrade to [UNK] — a quality loss, never a divergence.
//  - Punctuation detection covers ASCII punctuation plus the General
//    Punctuation block, matching BERT for all realistic corpus text.
//
// The ONNX runtime lands behind EdgeInferenceService in Phase 2 proper;
// this file is runtime-agnostic on purpose.

class WordPieceTokenizer {
  WordPieceTokenizer(List<String> vocabLines)
      : _vocab = {
          for (var i = 0; i < vocabLines.length; i++)
            vocabLines[i].trimRight(): i,
        } {
    unknownId = _requireId('[UNK]');
    clsId = _requireId('[CLS]');
    sepId = _requireId('[SEP]');
    padId = _requireId('[PAD]');
  }

  final Map<String, int> _vocab;

  late final int unknownId;
  late final int clsId;
  late final int sepId;
  late final int padId;

  static const String _continuation = '##';

  /// Longest word WordPiece will attempt before short-circuiting to
  /// [UNK] — mirrors BERT's max_input_chars_per_word.
  static const int maxWordChars = 100;

  int get vocabSize => _vocab.length;

  int _requireId(String token) {
    final id = _vocab[token];
    if (id == null) {
      throw ArgumentError('Vocabulary is missing required token $token');
    }
    return id;
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Sub-word tokens for [text] (lowercased, accent-folded, punctuation
  /// split), continuation pieces prefixed with `##`.
  List<String> tokenize(String text) {
    final pieces = <String>[];
    for (final word in _basicTokenize(text)) {
      pieces.addAll(_wordPiece(word));
    }
    return pieces;
  }

  /// Model-ready id sequence: `[CLS] … [SEP]`, hard-capped at [maxTokens]
  /// ids. Over-long input is truncated, never an error — user text length
  /// is not the caller's problem (EdgeInferenceService contract).
  List<int> encode(String text, {int maxTokens = 256}) {
    assert(maxTokens >= 2, 'need room for [CLS] and [SEP]');
    final pieces = tokenize(text);
    final budget = maxTokens - 2;
    final ids = <int>[
      clsId,
      for (final piece
          in pieces.length > budget ? pieces.sublist(0, budget) : pieces)
        _vocab[piece] ?? unknownId,
      sepId,
    ];
    return ids;
  }

  // -------------------------------------------------------------------------
  // Basic tokenizer (uncased)
  // -------------------------------------------------------------------------

  List<String> _basicTokenize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (_isControl(rune) || rune == 0xFFFD || rune == 0) continue;
      if (_isCjk(rune)) {
        // CJK ideographs tokenize per character in BERT.
        buffer
          ..write(' ')
          ..writeCharCode(rune)
          ..write(' ');
        continue;
      }
      buffer.writeCharCode(rune);
    }

    final words = <String>[];
    for (final raw in buffer.toString().split(RegExp(r'\s+'))) {
      if (raw.isEmpty) continue;
      final folded = _foldAccents(raw.toLowerCase());

      // Split punctuation into standalone tokens.
      final current = StringBuffer();
      for (final rune in folded.runes) {
        if (_isPunctuation(rune)) {
          if (current.isNotEmpty) {
            words.add(current.toString());
            current.clear();
          }
          words.add(String.fromCharCode(rune));
        } else {
          current.writeCharCode(rune);
        }
      }
      if (current.isNotEmpty) words.add(current.toString());
    }
    return words;
  }

  List<String> _wordPiece(String word) {
    if (word.length > maxWordChars) return const ['[UNK]'];

    final pieces = <String>[];
    var start = 0;
    while (start < word.length) {
      var end = word.length;
      String? match;
      while (start < end) {
        final candidate =
            (start > 0 ? _continuation : '') + word.substring(start, end);
        if (_vocab.containsKey(candidate)) {
          match = candidate;
          break;
        }
        end -= 1;
      }
      if (match == null) return const ['[UNK]']; // Whole word degrades.
      pieces.add(match);
      start = end;
    }
    return pieces;
  }

  // -------------------------------------------------------------------------
  // Character classes
  // -------------------------------------------------------------------------

  static bool _isControl(int rune) =>
      (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) ||
      (rune >= 0x7F && rune < 0xA0);

  static bool _isCjk(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x2A6DF);

  static bool _isPunctuation(int rune) =>
      (rune >= 33 && rune <= 47) ||
      (rune >= 58 && rune <= 64) ||
      (rune >= 91 && rune <= 96) ||
      (rune >= 123 && rune <= 126) ||
      (rune >= 0x2000 && rune <= 0x206F) || // General Punctuation
      rune == 0x00A1 || rune == 0x00BF || // ¡ ¿
      rune == 0x00AB || rune == 0x00BB; // « »

  /// Compact Latin accent fold — the practical subset of NFD+strip-marks.
  static String _foldAccents(String input) {
    const folds = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
      'ā': 'a', 'ē': 'e', 'ī': 'i', 'ō': 'o', 'ū': 'u',
      'ş': 's', 'ș': 's', 'ţ': 't', 'ț': 't', 'ž': 'z', 'š': 's',
      'č': 'c', 'ć': 'c', 'ł': 'l', 'ø': 'o', 'æ': 'ae', 'œ': 'oe',
      'ё': 'е', // Russian yo folds to ye, matching common search practice.
    };
    if (!folds.keys.any(input.contains)) return input;
    final out = StringBuffer();
    for (final char in input.split('')) {
      out.write(folds[char] ?? char);
    }
    return out.toString();
  }
}
