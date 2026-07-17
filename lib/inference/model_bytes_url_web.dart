// lib/inference/model_bytes_url_web.dart
//
// Web build: wraps model bytes from the asset bundle into a Blob URL so
// onnxruntime-web can fetch() them regardless of how the hosting page
// maps asset paths (production server, PWA cache, or the test harness).

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

Future<String?> blobUrlFromBytes(Uint8List bytes) async {
  final blobCtor = globalContext.getProperty('Blob'.toJS) as JSFunction;
  final parts = JSArray<JSAny?>();
  parts.callMethod('push'.toJS, bytes.toJS);
  final blob = blobCtor.callAsConstructor<JSObject>(parts);

  final urlApi = globalContext.getProperty('URL'.toJS) as JSObject;
  final url =
      urlApi.callMethod('createObjectURL'.toJS, blob) as JSString;
  return url.toDart;
}

void revokeBlobUrl(String url) {
  final urlApi = globalContext.getProperty('URL'.toJS) as JSObject;
  urlApi.callMethod('revokeObjectURL'.toJS, url.toJS);
}
