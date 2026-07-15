// Post-codegen workaround for stock isar_generator 3.1.0+1.
//
// The generator emits 64-bit schema/index ids as raw integer literals in
// *.g.dart. dart2js rejects any integer literal that is not exactly
// representable as a JS double (|v| > 2^53), which breaks `flutter build web`
// even though the web target never opens Isar (it uses the in-memory
// repository from lib/main.dart).
//
// This script rewrites every such literal V into the const expression
//   (q * 4294967296 + r)   where V == q * 2^32 + r, 0 <= r < 2^32.
// On the native VM the expression evaluates to exactly V (Isar schema ids
// are unchanged on Android/iOS). Under dart2js it const-folds to a lossy
// double, which is legal to compile and irrelevant at runtime on web.
//
// Run after every codegen:
//   dart run build_runner build --delete-conflicting-outputs
//   dart run tool/fix_web_ids.dart
//
// Idempotent: rewritten expressions contain no oversized literals, so a
// second run is a no-op. Remove this script if the project ever moves to a
// maintained Isar fork whose generator emits web-safe ids.

import 'dart:io';

final BigInt _two32 = BigInt.from(4294967296);
final BigInt _maxSafe = BigInt.from(9007199254740992); // 2^53

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.g.dart'));

  var patchedFiles = 0, patchedLiterals = 0;
  for (final file in files) {
    final source = file.readAsStringSync();
    var count = 0;
    final patched = source.replaceAllMapped(
      // A standalone (possibly negative) integer literal of 16+ digits.
      // 16 digits is the shortest decimal form that can exceed 2^53.
      RegExp(r'(^|[\s:,(\[=])(-?\d{16,})(?![\d\w])'),
      (m) {
        final value = BigInt.parse(m[2]!);
        if (value.abs() <= _maxSafe) return m[0]!;
        var r = value % _two32; // Dart %: result is non-negative here.
        if (r.isNegative) r += _two32;
        final q = (value - r) ~/ _two32;
        assert(q * _two32 + r == value);
        count++;
        return '${m[1]}($q * 4294967296 + $r)';
      },
    );
    if (count > 0) {
      file.writeAsStringSync(patched);
      patchedFiles++;
      patchedLiterals += count;
      stdout.writeln('patched $count literal(s) in ${file.path}');
    }
  }
  stdout.writeln(
    patchedFiles == 0
        ? 'no oversized literals found — nothing to do'
        : 'done: $patchedLiterals literal(s) across $patchedFiles file(s)',
  );
}
