// Phase 0 smoke test: the app root must build and render its first frames.
//
// The test environment reports TargetPlatform.android, so the permission
// gate is active; its permission_handler channel is stubbed to "granted"
// so the root proceeds to the boot screen. bootstrap() itself depends on
// platform channels that do not exist here and is intentionally left
// pending — the assertion targets the frame the boot screen paints.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app root builds and shows the boot screen', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            return 1; // PermissionStatus.granted
          case 'requestPermissions':
            final permissions = (call.arguments as List).cast<int>();
            return {for (final p in permissions) p: 1};
          default:
            return null;
        }
      },
    );

    await tester.pumpWidget(const AuraApp());
    expect(find.byType(MaterialApp), findsOneWidget);

    // Let the gate's async status check resolve; the next frame is the
    // composition root's boot screen.
    await tester.pump();
    expect(find.text('INITIALIZING MESH NODE'), findsOneWidget);
  });
}
