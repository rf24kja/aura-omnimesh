// Web wasm execution-provider verification. Runs ONLY under
//   flutter test --platform chrome test/onnx_web_test.dart
// Loads the same onnxruntime-web version the app vendors (from the CDN
// here, because the test harness does not serve web/ort/), then drives
// the REAL OnnxEmbeddingService: bundle asset -> blob URL -> wasm
// session -> beacon parity with the python int8 reference.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/inference/onnx_embedding_service.dart';

/// Python reference beacon for 'warm up' through the shipped int8 model
/// (tool/trim_model.py output). Web wasm kernels may differ in the last
/// bits — parity is asserted as cosine, not bitwise.
const referenceBeacon = [0.030133, 0.019173, 0.020602, 0.070352];

Future<void> _loadOrtScript() async {
  if (globalContext.hasProperty('ort'.toJS).toDart) return;
  final document = globalContext.getProperty('document'.toJS) as JSObject;
  final script =
      document.callMethod('createElement'.toJS, 'script'.toJS) as JSObject;
  script.setProperty(
    'src'.toJS,
    'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.23.0/dist/ort.min.js'
        .toJS,
  );
  final loaded = Completer<void>();
  script.setProperty(
    'onload'.toJS,
    (() => loaded.complete()).toJS,
  );
  script.setProperty(
    'onerror'.toJS,
    (() => loaded.completeError(StateError('ort.min.js failed to load')))
        .toJS,
  );
  final head = document.getProperty('head'.toJS) as JSObject;
  head.callMethod('appendChild'.toJS, script);
  await loaded.future;
}

double _cosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (na * nb == 0 ? 1 : (na * nb));
}

void main() {
  late OnnxEmbeddingService service;

  setUpAll(() async {
    await _loadOrtScript();
    service = OnnxEmbeddingService();
    await service.warmUp();
  });

  tearDownAll(() => service.dispose());

  test('beacon agrees with the python int8 reference', () async {
    final beacon = await service.generateEmbedding('warm up');
    expect(beacon, hasLength(384));
    // Per-dim agreement on the reference prefix — wasm vs native kernels
    // may drift in low bits, not in substance.
    for (var i = 0; i < referenceBeacon.length; i++) {
      expect(beacon[i], closeTo(referenceBeacon[i], 0.01),
          reason: 'beacon dim $i drifted');
    }
  });

  test('cross-lingual semantics survive the wasm runtime', () async {
    final offer =
        await service.generateEmbedding('weekly delivery of fresh vegetables');
    final need =
        await service.generateEmbedding('нужна доставка свежих овощей на дом');
    final unrelated =
        await service.generateEmbedding('уроки игры на гитаре с нуля');

    expect(_cosine(offer, need), greaterThan(0.45),
        reason: 'true cross-lingual pair must clear the ring threshold');
    expect(_cosine(offer, unrelated), lessThan(0.35),
        reason: 'unrelated pair must stay well below the threshold');
  });
}
