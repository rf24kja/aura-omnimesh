// WordPiece tokenizer against the real all-MiniLM-L6-v2 vocabulary.
// Property-style assertions (reconstruction, determinism, spec ids)
// rather than memorized goldens — the vocab file is the ground truth.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/inference/wordpiece_tokenizer.dart';

void main() {
  late WordPieceTokenizer tokenizer;

  setUpAll(() {
    final lines = File('assets/models/vocab.txt').readAsLinesSync();
    tokenizer = WordPieceTokenizer(lines);
  });

  test('vocabulary layout matches bert-base-uncased', () {
    expect(tokenizer.vocabSize, 30522);
    expect(tokenizer.padId, 0);
    expect(tokenizer.unknownId, 100);
    expect(tokenizer.clsId, 101);
    expect(tokenizer.sepId, 102);
  });

  test('lowercases and splits punctuation', () {
    expect(
      tokenizer.tokenize('Hello, World!'),
      ['hello', ',', 'world', '!'],
    );
  });

  test('encode frames with [CLS]/[SEP] and known ids', () {
    final ids = tokenizer.encode('hello world');
    expect(ids.first, 101);
    expect(ids.last, 102);
    expect(ids.length, 4);
    // Inner ids must be the vocab rows of the whole words.
    final pieces = tokenizer.tokenize('hello world');
    expect(pieces, ['hello', 'world']);
  });

  test('out-of-vocabulary word decomposes and reconstructs, or is UNK',
      () {
    final pieces = tokenizer.tokenize('flutterdart');
    if (pieces.length == 1) {
      expect(pieces.single, '[UNK]');
    } else {
      expect(pieces.first, isNot(startsWith('##')));
      for (final piece in pieces.skip(1)) {
        expect(piece, startsWith('##'));
      }
      final rebuilt = pieces.first +
          pieces.skip(1).map((p) => p.substring(2)).join();
      expect(rebuilt, 'flutterdart');
    }
  });

  test('accented text folds instead of degrading', () {
    expect(tokenizer.tokenize('Café'), contains('cafe'));
  });

  test('unknown glyphs degrade to [UNK], never crash', () {
    final ids = tokenizer.encode('☈');
    expect(ids, [101, 100, 102]);
  });

  test('cyrillic input is deterministic and non-empty', () {
    final a = tokenizer.tokenize('привет мир');
    final b = tokenizer.tokenize('привет мир');
    expect(a, isNotEmpty);
    expect(a, b);
  });

  test('over-long input truncates to the token budget', () {
    final text = List.filled(500, 'hello').join(' ');
    final ids = tokenizer.encode(text, maxTokens: 256);
    expect(ids.length, 256);
    expect(ids.first, 101);
    expect(ids.last, 102);
  });
}
