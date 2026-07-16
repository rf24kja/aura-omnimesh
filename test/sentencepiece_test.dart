// SentencePiece Unigram tokenizer vs the PYTHON tokenizers reference
// (the Rust implementation — the authority; transformers.js has a known
// non-BMP normalizer bug). Goldens are generated against the TRIMMED
// vocabulary by tool/trim_model.py and live in
// test/sentencepiece_goldens.json — regenerate them whenever the model
// asset changes. Byte-exact id sequences: any drift means devices would
// embed the same text differently than the reference runtime.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/inference/sentencepiece_tokenizer.dart';

void main() {
  late SentencePieceUnigramTokenizer tokenizer;
  late Map<String, dynamic> goldens;

  setUpAll(() {
    tokenizer = SentencePieceUnigramTokenizer(
      File('assets/models/xlmr_vocab_trimmed_v1.tsv').readAsLinesSync(),
    );
    goldens = jsonDecode(
      File('test/sentencepiece_goldens.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('vocabulary size matches the goldens generation', () {
    expect(tokenizer.vocabSize, goldens['vocabSize']);
  });

  test('all reference goldens are byte-exact', () {
    final cases = goldens['cases'] as Map<String, dynamic>;
    expect(cases, isNotEmpty);
    for (final entry in cases.entries) {
      expect(
        tokenizer.encode(entry.key),
        (entry.value as List).cast<int>(),
        reason: 'tokenization drift for "${entry.key}"',
      );
    }
  });

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
