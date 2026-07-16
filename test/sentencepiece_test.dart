// SentencePiece Unigram tokenizer vs transformers.js goldens for
// Xenova/paraphrase-multilingual-MiniLM-L12-v2 (generated 2026-07-16).
// Byte-exact id sequences — any drift here means devices would embed the
// same text differently than the reference runtime.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/inference/sentencepiece_tokenizer.dart';

const Map<String, List<int>> goldens = {
  'hello world': [0, 33600, 31, 8999, 2],
  'dart programming lessons for beginners': [
    0, 1011, 18, 56037, 449, 182417, 100, 9842, 43148, 2,
  ],
  'привет мир': [0, 146038, 11373, 2],
  'помочь разобраться с флаттером и дартом': [
    0, 81871, 169291, 135, 97197, 87332, 419, 35, 30398, 13449, 2,
  ],
  'Отдам детскую коляску, в хорошем состоянии!': [
    0, 3858, 21288, 6, 26435, 24499, 14166, 245, 7888, 4, 49, 46604, 1551,
    68849, 38, 2,
  ],
  'weekly delivery of fresh vegetables': [
    0, 5895, 538, 117989, 111, 63335, 231718, 2,
  ],
  'C++ и Flutter-разработка 2026': [
    0, 313, 37223, 35, 36157, 3055, 9, 4968, 78238, 387, 4046, 2,
  ],
  '  multiple   spaces  here  ': [0, 48716, 32628, 7, 3688, 2],
  'ёлка и Ёж': [0, 6, 48841, 415, 35, 6, 57498, 861, 2],
  // Non-BMP goldens arbitrated by PYTHON tokenizers (the Rust reference):
  // transformers.js drops non-BMP chars in its Precompiled normalizer and
  // wrongly yields <unk> here — our output matches the authority.
  '🦄🦄 unicorn': [0, 6, 247874, 247874, 60347, 42, 19, 2],
  'test 🦄 mid': [0, 3034, 6, 247874, 4122, 2],
  // True unknown (no vocab piece): fuse_unk collapses the run to one <unk>.
  '˧˧˧': [0, 6, 3, 2],
};

void main() {
  late SentencePieceUnigramTokenizer tokenizer;

  setUpAll(() {
    tokenizer = SentencePieceUnigramTokenizer(
      File('assets/models/xlmr_unigram_vocab.tsv').readAsLinesSync(),
    );
  });

  test('vocabulary loads with the XLM-R layout', () {
    expect(tokenizer.vocabSize, 250002);
  });

  for (final entry in goldens.entries) {
    test('golden: "${entry.key}"', () {
      expect(tokenizer.encode(entry.key), entry.value);
    });
  }

  test('deterministic across calls', () {
    const text = 'помогу перевезти мебель в выходные';
    expect(tokenizer.encode(text), tokenizer.encode(text));
  });

  test('over-long input truncates to the budget with framing intact', () {
    final text = List.filled(400, 'слово word').join(' ');
    final ids = tokenizer.encode(text, maxTokens: 128);
    expect(ids.length, lessThanOrEqualTo(128));
    expect(ids.first, SentencePieceUnigramTokenizer.bosId);
    expect(ids.last, SentencePieceUnigramTokenizer.eosId);
  });
}
