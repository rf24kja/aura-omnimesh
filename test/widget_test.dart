// Phase 0 smoke test: the app root must build and render its first frame.
//
// bootstrap() is asynchronous and depends on platform channels that do not
// exist in the test environment, so this pumps exactly one frame and asserts
// the boot screen is shown — enough to catch any construction-time regression
// in the composition root.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/main.dart';

void main() {
  testWidgets('app root builds and shows the boot screen', (tester) async {
    await tester.pumpWidget(const AuraApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('INITIALIZING MESH NODE'), findsOneWidget);
  });
}
