// Widget tests for the EXCHANGE pane over the REAL adapter pipeline:
// InMemory repository → RingMatchFacade → MeshUiAdapter → DashboardView.
// Only the radio transport is faked; everything above it is production
// code, so these tests break when the real wiring breaks.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/swarm_compute_gate.dart';
import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/mesh_sync_engine.dart';
import 'package:omnimesh/main.dart';
import 'package:omnimesh/matching/ring_matcher.dart';
import 'package:omnimesh/services/services.dart';
import 'package:omnimesh/ui/app_theme.dart';
import 'package:omnimesh/ui/dashboard_view.dart';
import 'package:omnimesh/ui/mesh_ui_adapter.dart';

class _FakeTransport implements LocalMeshTransportService {
  final _nodes = StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltas = StreamController<List<CrdtStateLog>>.broadcast();

  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered => _nodes.stream;

  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltas.stream;

  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {}

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<void> broadcastDelta(List<CrdtStateLog> elements) async {}

  @override
  Future<void> sendDeltaToPeer(
    String peerPublicKey,
    List<CrdtStateLog> elements,
  ) async {}

  @override
  Future<void> dispose() async {
    await _nodes.close();
    await _deltas.close();
  }
}

ResourceIntent _intent({
  required String uuid,
  required String owner,
  required IntentDirection direction,
  required int axis,
  String? rawText,
  IntentStatus status = IntentStatus.open,
}) {
  final vector = List<double>.filled(kEmbeddingDimensions, 0.0)..[axis] = 1.0;
  return ResourceIntent(
    intentUuid: uuid,
    originNodeKey: owner,
    allocationCategory: AllocationCategory.peerExchange,
    rawTextPayload: rawText ?? uuid,
    vectorData: vector,
    structuralQuantity: 1,
    epochTimestamp: 0,
    direction: direction,
  )..status = status;
}

void main() {
  late InMemoryMeshRepository repository;
  late _FakeTransport transport;
  late MeshSyncEngine engine;
  late MeshUiAdapter adapter;
  late Ed25519IdentitySigner self;

  Future<void> buildStack() async {
    repository = InMemoryMeshRepository();
    transport = _FakeTransport();
    final materializer = CrdtMaterializer(repository);
    engine = MeshSyncEngine(
      repository: repository,
      transport: transport,
      applier: materializer,
    );
    self = await Ed25519IdentitySigner.generate();
    adapter = MeshUiAdapter(
      engine: engine,
      repository: repository,
      ringFacade: RingMatchFacade(repository: repository),
      signer: self,
    );
  }

  Widget host() => MaterialApp(
        theme: AuraTheme.dark(),
        home: DashboardView(
          adapter: adapter,
          computeGate: SwarmComputeGate(trustedSsids: const {}),
          repository: repository,
          onCommandSubmitted: (_) async {},
        ),
      );

  testWidgets('empty mesh shows the listening state', (tester) async {
    await tester.runAsync(() async {
      await buildStack();
      await adapter.attach();
    });
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('MESH LISTENING'), findsOneWidget);
    expect(find.text('CLOSED LOOPS'), findsNothing);
  });

  testWidgets(
      'discovered self-involving ring renders card, trust and action',
      (tester) async {
    await tester.runAsync(() async {
      await buildStack();
      const bKey =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const cKey =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      await repository.upsertNodeIdentity(NodeIdentity(
        cryptographicPublicKey: bKey,
        localAlias: 'beta',
        reliabilityScore: 30,
      ));
      await repository.upsertNodeIdentity(NodeIdentity(
        cryptographicPublicKey: cKey,
        localAlias: 'gamma',
        reliabilityScore: 0,
      ));
      // Self offers axis0 which beta needs; beta offers axis1 which gamma
      // needs; gamma offers axis2 which self needs — a closed 3-loop.
      final rows = [
        _intent(uuid: 'self-off', owner: self.publicKeyHex,
            direction: IntentDirection.offer, axis: 0,
            rawText: 'dart tutoring'),
        _intent(uuid: 'b-need', owner: bKey,
            direction: IntentDirection.need, axis: 0),
        _intent(uuid: 'b-off', owner: bKey,
            direction: IntentDirection.offer, axis: 1,
            rawText: 'scooter loan'),
        _intent(uuid: 'c-need', owner: cKey,
            direction: IntentDirection.need, axis: 1),
        _intent(uuid: 'c-off', owner: cKey,
            direction: IntentDirection.offer, axis: 2,
            rawText: 'groceries'),
        _intent(uuid: 'self-need', owner: self.publicKeyHex,
            direction: IntentDirection.need, axis: 2),
      ];
      for (final row in rows) {
        await repository.upsertIntent(row);
      }
      await adapter.attach();
    });
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('CLOSED LOOPS'), findsOneWidget);
    expect(find.text('INCLUDES YOU'), findsOneWidget);
    expect(find.text('3-PARTY LOOP'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    // Known peer with history shows trust; zero-score peer stays silent.
    expect(find.text('TRUST 30'), findsOneWidget);
    expect(find.text('TRUST 0'), findsNothing);
    // 800 lp test surface -> wide layout -> explicit ROUTE action.
    expect(find.text('ROUTE'), findsOneWidget);
  });

  testWidgets('confirmed routed ring shows progress and fulfil action',
      (tester) async {
    await tester.runAsync(() async {
      await buildStack();
      const bKey =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const ringId = 'hop-a>hop-b';
      // Two-hop ring, both offers already locked (materialized view).
      await repository.upsertIntent(_intent(
          uuid: 'hop-a', owner: self.publicKeyHex,
          direction: IntentDirection.offer, axis: 0,
          rawText: 'dart tutoring',
          status: IntentStatus.lockedInLoop));
      await repository.upsertIntent(_intent(
          uuid: 'hop-b', owner: bKey,
          direction: IntentDirection.offer, axis: 1,
          rawText: 'scooter loan',
          status: IntentStatus.lockedInLoop));
      // Lock ops in the log make the ring "routed"; the assembly reads
      // trust from materialized rows, not from these payloads.
      await repository.appendDeltas([
        CrdtStateLog(
          transactionUuid: 'tx-lock-a',
          targetIntentUuid: 'hop-a',
          authoritySignature: '',
          lamportLogicalClock: 2,
          operationPayloadJson:
              '{"op":"lock_intent","intentUuid":"hop-a",'
              '"ringId":"$ringId","author":"${self.publicKeyHex}"}',
        ),
        CrdtStateLog(
          transactionUuid: 'tx-lock-b',
          targetIntentUuid: 'hop-b',
          authoritySignature: '',
          lamportLogicalClock: 2,
          operationPayloadJson:
              '{"op":"lock_intent","intentUuid":"hop-b",'
              '"ringId":"$ringId","author":"$bKey"}',
        ),
      ]);
      await adapter.attach();
    });
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('ROUTED LOOPS'), findsOneWidget);
    expect(find.text('CONFIRMED — ALL HOPS LOCKED'), findsOneWidget);
    expect(find.text('MARK FULFILLED'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('LOCKED'), findsNWidgets(2));
  });

  testWidgets('own intents surface with withdraw; tap authors a withdraw',
      (tester) async {
    await tester.runAsync(() async {
      await buildStack();
      // Real signed create op so the materializer fold owns the row —
      // that is what makes the withdraw fold-through work end to end.
      final create = jsonStablePayload(
        op: 'create_intent',
        author: self.publicKeyHex,
        intent: <String, dynamic>{
          'intentUuid': 'mine-open',
          'originNodeKey': self.publicKeyHex,
          'category': 'peer_exchange',
          'direction': 'offer',
          'rawText': 'dart tutoring for beginners',
          'vector': List<double>.filled(kEmbeddingDimensions, 0.0)..[0] = 1.0,
          'quantity': 1,
          'epochMs': 2000,
        },
      );
      await engine.publishLocalDeltas([
        CrdtStateLog(
          transactionUuid: 'tx-create-mine',
          targetIntentUuid: 'mine-open',
          authoritySignature:
              await self.signToHex(crdtSignaturePreimage(create, 1)),
          lamportLogicalClock: 1,
          operationPayloadJson: create,
        ),
      ]);
      // A satisfied intent (row-only) — must show but not be withdrawable.
      await repository.upsertIntent(_intent(
          uuid: 'mine-done', owner: self.publicKeyHex,
          direction: IntentDirection.need, axis: 1,
          rawText: 'groceries', status: IntentStatus.satisfied));
      await adapter.attach();
    });
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('MY INTENTS'), findsOneWidget);
    expect(find.text('dart tutoring for beginners'), findsOneWidget);
    // Live intent is withdrawable; the satisfied one is not.
    expect(find.text('WITHDRAW'), findsOneWidget);

    await tester.tap(find.text('WITHDRAW'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 500));

    // The withdraw op folded the row into the absorbing withdrawn state,
    // so it is no longer withdrawable.
    await tester.runAsync(() async {
      final row = await repository.findIntentByUuid('mine-open');
      expect(row!.status, IntentStatus.withdrawn);
    });
  });
}
