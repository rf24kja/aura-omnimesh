// Identity onboarding: the alias/public-key screen must show the REAL
// key the node will use, persist the chosen alias, and never appear
// again once one is stored.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/ui/app_theme.dart';
import 'package:omnimesh/ui/identity_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageKey = 'test.alias';
  late Map<String, String> storage;
  late Ed25519IdentitySigner signer;

  setUp(() async {
    storage = {};
    signer = await Ed25519IdentitySigner.generate();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        switch (call.method) {
          case 'read':
            return storage[args['key']];
          case 'write':
            storage[args['key'] as String] = args['value'] as String;
            return null;
          default:
            return null;
        }
      },
    );
  });

  Widget host() => MaterialApp(
        theme: AuraTheme.dark(),
        home: IdentityGate(
          aliasStorageKey: storageKey,
          loadSigner: () async => signer,
          builder: (_) => const Text('BOOTED'),
        ),
      );

  testWidgets('shows the real public key and persists the chosen alias',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    expect(find.text('MESH IDENTITY'), findsOneWidget);
    // The full key is rendered (grouped) — check a recognizable chunk.
    expect(
      find.textContaining(signer.publicKeyHex.substring(0, 8)),
      findsOneWidget,
    );
    // Suggested alias derives from the key.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text,
        'node-${signer.publicKeyHex.substring(0, 6)}');

    await tester.enterText(find.byType(TextField), 'ringmaster');
    await tester.tap(find.text('ENTER THE MESH'));
    await tester.pump();
    await tester.pump();

    expect(storage[storageKey], 'ringmaster');
    expect(find.text('BOOTED'), findsOneWidget);
  });

  testWidgets('a stored alias skips the screen entirely', (tester) async {
    storage[storageKey] = 'veteran';
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('BOOTED'), findsOneWidget);
    expect(find.text('MESH IDENTITY'), findsNothing);
  });

  testWidgets('empty alias is rejected — the gate stays', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('ENTER THE MESH'));
    await tester.pump();

    expect(storage.containsKey(storageKey), isFalse);
    expect(find.text('MESH IDENTITY'), findsOneWidget);
  });
}
