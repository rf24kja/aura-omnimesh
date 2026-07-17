// lib/inference/model_bytes_url_stub.dart
//
// Native build: model loading goes through the plugin's
// createSessionFromAsset (file extraction + by-name caching), so the
// blob-URL path is never taken.

import 'dart:typed_data';

Future<String?> blobUrlFromBytes(Uint8List bytes) async => null;

void revokeBlobUrl(String url) {}
