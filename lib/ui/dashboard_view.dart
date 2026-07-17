// lib/ui/dashboard_view.dart
//
// FILE 13 — Tri-module application shell binding all three product
// surfaces to the runtime:
//   EXCHANGE (Module A / FluidMesh): spotlight command line + discovered
//     barter rings, swipe-to-route on touch, click-to-route on desktop.
//   COMPUTE (Module B / SwarmCompute): hardware telemetry cockpit driven
//     by SwarmComputeGate, with the NPU/GPU opt-in toggle.
//   GRID (Module C / VoltMesh): energy telemetry tiles materialized from
//     local Isar rows — layout-ready for the Modbus/MQTT gateway.
//
// Responsive contract: full-bleed below 720 lp; centered 720 px column
// with 1 px slate rails on desktop PWA widths. Wide layouts swap swipe
// gestures for explicit actions (a desktop pointer has no Dismissible).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../compute/swarm_compute_gate.dart';
import '../domain/domain_models.dart';
import '../services/services.dart';
import '../transport/bridge_handle.dart';
import 'app_theme.dart';
import 'mesh_ui_adapter.dart';

enum _Module { exchange, compute, grid }

class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.adapter,
    required this.computeGate,
    required this.repository,
    required this.onCommandSubmitted,
    this.bridge,
  });

  final MeshUiAdapter adapter;
  final SwarmComputeGate computeGate;
  final MeshRepository repository;
  final Future<void> Function(String command) onCommandSubmitted;

  /// Core Node LAN bridge; null on web Light Clients (no pairing surface).
  final BridgeHandle? bridge;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  static const double _contentMaxWidth = 720;

  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocus = FocusNode();

  _Module _module = _Module.exchange;
  bool _submitting = false;

  /// Non-null while acceptRing is in flight — drives the blocking
  /// transition overlay.
  String? _lockingRingId;

  /// Non-null while satisfyRing is in flight.
  String? _fulfillingRingId;

  /// Non-null while a withdrawIntent is in flight.
  String? _withdrawingUuid;

  /// Compute opt-in. Opting out stops the gate entirely: no polling, no
  /// eligibility, no work — the strongest possible "out".
  bool _computeOptIn = true;

  /// Module C corpus, reloaded when the local clock advances.
  List<ResourceIntent> _energyIntents = const [];
  int _lastSeenClock = -1;

  @override
  void initState() {
    super.initState();
    widget.adapter.state.addListener(_onAdapterState);
    _reloadEnergy();
  }

  @override
  void dispose() {
    widget.adapter.state.removeListener(_onAdapterState);
    _commandController.dispose();
    _commandFocus.dispose();
    super.dispose();
  }

  void _onAdapterState() {
    final clock = widget.adapter.state.value.localClock;
    if (clock != _lastSeenClock) {
      _lastSeenClock = clock;
      _reloadEnergy();
    }
  }

  Future<void> _reloadEnergy() async {
    final rows = await widget.repository.readIntentsByCategory(
      AllocationCategory.energyTelemetry,
    );
    rows.sort((a, b) => b.epochTimestamp.compareTo(a.epochTimestamp));
    if (!mounted) return;
    setState(() => _energyIntents = List.unmodifiable(rows));
  }

  // -------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------

  Future<void> _handleSubmit(String raw) async {
    final command = raw.trim();
    if (command.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onCommandSubmitted(command);
      _commandController.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        _commandFocus.requestFocus();
      }
    }
  }

  Future<void> _acceptRing(String ringId) async {
    if (_lockingRingId != null) return; // One lock at a time.
    HapticFeedback.selectionClick();
    setState(() => _lockingRingId = ringId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.adapter.acceptRing(ringId);
      messenger.showSnackBar(const SnackBar(
        content: Text('RING LOCKED — GOSSIPING CONFIRMATION',
            style: AuraType.label),
      ));
    } on StateError {
      messenger.showSnackBar(const SnackBar(
        content: Text('RING EXPIRED — THE GRAPH CHANGED',
            style: AuraType.label),
      ));
    } finally {
      if (mounted) setState(() => _lockingRingId = null);
    }
  }

  Future<void> _fulfilRing(String ringId) async {
    if (_fulfillingRingId != null || _lockingRingId != null) return;
    HapticFeedback.selectionClick();
    setState(() => _fulfillingRingId = ringId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.adapter.satisfyRing(ringId);
      messenger.showSnackBar(const SnackBar(
        content: Text('EXCHANGE FULFILLED — GOSSIPING PROOF',
            style: AuraType.label),
      ));
    } on StateError {
      messenger.showSnackBar(const SnackBar(
        content: Text('NOTHING TO FULFIL IN THIS RING',
            style: AuraType.label),
      ));
    } finally {
      if (mounted) setState(() => _fulfillingRingId = null);
    }
  }

  Future<void> _withdrawIntent(String intentUuid) async {
    if (_withdrawingUuid != null) return;
    HapticFeedback.selectionClick();
    setState(() => _withdrawingUuid = intentUuid);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.adapter.withdrawIntent(intentUuid);
      messenger.showSnackBar(const SnackBar(
        content: Text('INTENT WITHDRAWN — GOSSIPING', style: AuraType.label),
      ));
    } on StateError {
      messenger.showSnackBar(const SnackBar(
        content: Text('CANNOT WITHDRAW — NOT YOURS OR ALREADY CLOSED',
            style: AuraType.label),
      ));
    } finally {
      if (mounted) setState(() => _withdrawingUuid = null);
    }
  }

  Future<void> _showPairDialog() async {
    final bridge = widget.bridge;
    if (bridge == null) return;
    final endpoints = await bridge.pairingEndpoints();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: AuraColors.scrim,
      builder: (context) => _PairDialog(endpoints: endpoints),
    );
  }

  void _toggleComputeOptIn(bool value) {
    setState(() => _computeOptIn = value);
    if (value) {
      widget.computeGate.start();
    } else {
      widget.computeGate.stop(); // Gate reverts to indeterminate.
    }
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraColors.obsidian,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > _contentMaxWidth;
            final column = _buildColumn(isWide);

            final framed = isWide
                ? Center(
                    child: Container(
                      constraints: const BoxConstraints(
                          maxWidth: _contentMaxWidth),
                      decoration: const BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(
                            color: AuraColors.slate,
                            width: AuraStroke.line,
                          ),
                        ),
                      ),
                      child: column,
                    ),
                  )
                : column;

            return Stack(
              children: [
                framed,
                if (_lockingRingId != null)
                  const _TransitionOverlay(
                      label: 'LOCKING RING — SIGNING & GOSSIPING'),
                if (_fulfillingRingId != null)
                  const _TransitionOverlay(
                      label: 'FULFILLING — SIGNING & GOSSIPING'),
                if (_withdrawingUuid != null)
                  const _TransitionOverlay(
                      label: 'WITHDRAWING — SIGNING & GOSSIPING'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildColumn(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_module == _Module.exchange)
          ValueListenableBuilder<MeshUiState>(
            valueListenable: widget.adapter.state,
            builder: (context, mesh, _) => _SpotlightInput(
              controller: _commandController,
              focusNode: _commandFocus,
              enabled: !_submitting,
              busy: _submitting || mesh.isMatching,
              onSubmitted: _handleSubmit,
            ),
          ),
        _ModuleNav(
          active: _module,
          onSelect: (module) => setState(() => _module = module),
          onPair: widget.bridge == null ? null : _showPairDialog,
        ),
        Expanded(
          child: switch (_module) {
            _Module.exchange => _ExchangePane(
                adapter: widget.adapter,
                isWide: isWide,
                lockingRingId: _lockingRingId,
                withdrawingUuid: _withdrawingUuid,
                onAccept: _acceptRing,
                onFulfil: _fulfilRing,
                onWithdraw: _withdrawIntent,
              ),
            _Module.compute => _ComputePane(
                gate: widget.computeGate,
                optedIn: _computeOptIn,
                onToggle: _toggleComputeOptIn,
              ),
            _Module.grid => _GridPane(
                intents: _energyIntents,
                isWide: isWide,
              ),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Chrome: spotlight input, module navigation, transition overlay
// ---------------------------------------------------------------------

class _SpotlightInput extends StatelessWidget {
  const _SpotlightInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.busy,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool busy;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AuraSpace.s2,
        vertical: AuraSpace.s1,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AuraColors.slate, width: AuraStroke.line),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: true,
              cursorColor: AuraColors.type,
              cursorWidth: 2,
              style: AuraType.input,
              textInputAction: TextInputAction.send,
              onFieldSubmitted: onSubmitted,
              inputFormatters: [LengthLimitingTextInputFormatter(512)],
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'offer: …  ·  need: …',
                hintStyle: AuraType.inputHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    EdgeInsets.symmetric(vertical: AuraSpace.s1),
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(left: AuraSpace.s2),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModuleNav extends StatelessWidget {
  const _ModuleNav({
    required this.active,
    required this.onSelect,
    this.onPair,
  });

  final _Module active;
  final ValueChanged<_Module> onSelect;

  /// Opens the Light Client pairing QR; null on targets without a bridge.
  final VoidCallback? onPair;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AuraColors.hairline, width: AuraStroke.hair),
        ),
      ),
      child: Row(
        children: [
          _navItem('EXCHANGE', _Module.exchange),
          _navItem('COMPUTE', _Module.compute),
          _navItem('GRID', _Module.grid),
          if (onPair != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPair,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AuraSpace.s2,
                  vertical: AuraSpace.s2,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: AuraColors.hairline,
                        width: AuraStroke.hair),
                  ),
                ),
                child: Text('PAIR', style: AuraType.label),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navItem(String label, _Module module) {
    final isActive = module == active;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(module),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AuraSpace.s2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AuraColors.type : Colors.transparent,
                width: AuraStroke.line,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: isActive
                ? AuraType.label.copyWith(color: AuraColors.type)
                : AuraType.label,
          ),
        ),
      ),
    );
  }
}

class _TransitionOverlay extends StatelessWidget {
  const _TransitionOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // AbsorbPointer semantics via an opaque full-screen surface: every
    // tap lands here and dies until the lock round completes.
    return Positioned.fill(
      child: Container(
        color: AuraColors.scrim,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(height: AuraSpace.s2),
            Text(label,
                style: AuraType.label.copyWith(color: AuraColors.type)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Module A — EXCHANGE
// ---------------------------------------------------------------------

class _ExchangePane extends StatelessWidget {
  const _ExchangePane({
    required this.adapter,
    required this.isWide,
    required this.lockingRingId,
    required this.withdrawingUuid,
    required this.onAccept,
    required this.onFulfil,
    required this.onWithdraw,
  });

  final MeshUiAdapter adapter;
  final bool isWide;
  final String? lockingRingId;
  final String? withdrawingUuid;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onFulfil;
  final ValueChanged<String> onWithdraw;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MeshUiState>(
      valueListenable: adapter.state,
      builder: (context, mesh, _) {
        final rings = mesh.discoveredRings;
        final routed = mesh.routedRings;
        final own = mesh.ownIntents;
        if (rings.isEmpty && routed.isEmpty && own.isEmpty) {
          return const _EmptyState(
            title: 'MESH LISTENING',
            detail: 'No closed exchange loops yet. Publish offers and '
                'needs — rings surface the moment a cycle closes.',
          );
        }
        final children = <Widget>[
          if (rings.isNotEmpty)
            const _SectionHeader(label: 'CLOSED LOOPS'),
          for (final ring in rings) _discoveredEntry(ring),
          if (routed.isNotEmpty)
            const _SectionHeader(label: 'ROUTED LOOPS'),
          for (final ring in routed)
            _RoutedRingCard(
              ring: ring,
              onFulfil: () => onFulfil(ring.ringId),
            ),
          if (own.isNotEmpty)
            const _SectionHeader(label: 'MY INTENTS'),
          for (final intent in own)
            _OwnIntentRow(
              intent: intent,
              busy: intent.intentUuid == withdrawingUuid,
              onWithdraw: () => onWithdraw(intent.intentUuid),
            ),
        ];
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: AuraSpace.s1),
          children: children,
        );
      },
    );
  }

  Widget _discoveredEntry(RingVm ring) {
    final card = _RingCard(
      ring: ring,
      isWide: isWide,
      locking: ring.ringId == lockingRingId,
      onAccept: () => onAccept(ring.ringId),
    );
    if (isWide) return card; // Pointer world: explicit action.
    return Dismissible(
      key: ValueKey('ring-${ring.ringId}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        color: AuraColors.obsidian,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AuraSpace.s2),
        child: Text('ROUTE →',
            style: AuraType.label.copyWith(color: AuraColors.type)),
      ),
      confirmDismiss: (_) async {
        // State-driven UI safeguard: never let Dismissible remove
        // the row — the post-lock rematch snapshot does.
        onAccept(ring.ringId);
        return false;
      },
      child: card,
    );
  }
}

/// One row of the MY INTENTS management surface: the author's view of a
/// published intent with a withdraw affordance while it is still live.
class _OwnIntentRow extends StatelessWidget {
  const _OwnIntentRow({
    required this.intent,
    required this.busy,
    required this.onWithdraw,
  });

  final OwnIntentVm intent;
  final bool busy;
  final VoidCallback onWithdraw;

  ({String word, Color stroke}) get _status => switch (intent.status) {
        IntentStatus.open => (word: 'OPEN', stroke: AuraColors.slate),
        IntentStatus.lockedInLoop => (
            word: 'LOCKED',
            stroke: AuraColors.emerald,
          ),
        IntentStatus.satisfied => (
            word: 'SATISFIED',
            stroke: AuraColors.emerald,
          ),
        IntentStatus.withdrawn => (
            word: 'WITHDRAWN',
            stroke: AuraColors.amber,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AuraSpace.s2, 0, AuraSpace.s2, AuraSpace.s1),
      padding: const EdgeInsets.all(AuraSpace.s2),
      decoration: BoxDecoration(
        color: AuraColors.carbon,
        border: Border.all(color: AuraColors.slate, width: AuraStroke.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AuraStroke.indicator,
            height: AuraSpace.s3,
            margin: const EdgeInsets.only(top: 2),
            color: status.stroke,
          ),
          const SizedBox(width: AuraSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${intent.direction == IntentDirection.offer ? 'OFFER' : 'NEED'}'
                  '  ·  ${status.word}',
                  style: AuraType.label,
                ),
                const SizedBox(height: 4),
                Text(intent.text,
                    style: AuraType.bodyDim,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (intent.canWithdraw) ...[
            const SizedBox(width: AuraSpace.s2),
            GestureDetector(
              onTap: busy ? null : onWithdraw,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AuraSpace.s2, vertical: AuraSpace.s1),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: AuraColors.slate, width: AuraStroke.line),
                ),
                child: Text('WITHDRAW', style: AuraType.label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Accepted ring tracked through lock confirmation to fulfilment.
/// Color discipline: emerald indicator stroke only when the protocol
/// reached a verified-good state (confirmed/completed); amber only for
/// the broken case. Everything else stays monochrome.
class _RoutedRingCard extends StatelessWidget {
  const _RoutedRingCard({required this.ring, required this.onFulfil});

  final RoutedRingVm ring;
  final VoidCallback onFulfil;

  ({String label, Color stroke}) get _phase {
    if (ring.broken) {
      return (label: 'BROKEN — PARTICIPANT WITHDREW', stroke: AuraColors.amber);
    }
    if (ring.completed) {
      return (label: 'COMPLETED', stroke: AuraColors.emerald);
    }
    if (ring.confirmed) {
      return (label: 'CONFIRMED — ALL HOPS LOCKED', stroke: AuraColors.emerald);
    }
    return (
      label: '${ring.committedCount}/${ring.hopCount} LOCKED',
      stroke: AuraColors.slate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AuraSpace.s2, 0, AuraSpace.s2, AuraSpace.s2),
      padding: const EdgeInsets.all(AuraSpace.s2),
      decoration: BoxDecoration(
        color: AuraColors.carbon,
        border:
            Border.all(color: AuraColors.slate, width: AuraStroke.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AuraStroke.indicator,
                height: AuraSpace.s2,
                color: phase.stroke,
              ),
              const SizedBox(width: AuraSpace.s1),
              Expanded(child: Text(phase.label, style: AuraType.label)),
              Text('${ring.hopCount}-PARTY', style: AuraType.label),
            ],
          ),
          const SizedBox(height: AuraSpace.s2),
          for (final hop in ring.hops)
            Padding(
              padding: const EdgeInsets.only(bottom: AuraSpace.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      hop.isSelf ? 'YOU' : hop.alias,
                      style: hop.isSelf
                          ? AuraType.label.copyWith(color: AuraColors.type)
                          : AuraType.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(hop.gives,
                        style: AuraType.bodyDim,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: AuraSpace.s1),
                  Text(
                    switch (hop.status) {
                      IntentStatus.open => 'PENDING',
                      IntentStatus.lockedInLoop => 'LOCKED',
                      IntentStatus.satisfied => 'DONE',
                      IntentStatus.withdrawn => 'WITHDREW',
                    },
                    style: AuraType.label,
                  ),
                ],
              ),
            ),
          if (ring.canFulfil) ...[
            const SizedBox(height: AuraSpace.s1),
            Row(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: onFulfil,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AuraSpace.s2, vertical: AuraSpace.s1),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AuraColors.type, width: AuraStroke.line),
                    ),
                    child: Text('MARK FULFILLED',
                        style:
                            AuraType.label.copyWith(color: AuraColors.type)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Pairing dialog: every LAN endpoint as a scannable QR. The QR module
/// field is deliberately paper-white — a scanner-hostile inverted code
/// would be aesthetics over function.
class _PairDialog extends StatelessWidget {
  const _PairDialog({required this.endpoints});

  final List<Uri> endpoints;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AuraColors.obsidian,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AuraColors.slate, width: AuraStroke.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AuraSpace.s3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PAIR LIGHT CLIENT', style: AuraType.label),
            const SizedBox(height: AuraSpace.s1),
            const Text(
              'Open the web client on a device in this network and scan, '
              'or append ?bridge=<endpoint> to its URL.',
              style: AuraType.bodyDim,
            ),
            const SizedBox(height: AuraSpace.s2),
            if (endpoints.isEmpty)
              const Text(
                'NO LAN ADDRESS — JOIN A WI-FI NETWORK FIRST',
                style: AuraType.label,
              )
            else
              for (final endpoint in endpoints) ...[
                Center(
                  child: Container(
                    color: AuraColors.type,
                    padding: const EdgeInsets.all(AuraSpace.s2),
                    child: QrImageView(
                      data: endpoint.toString(),
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: AuraColors.type,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AuraColors.obsidian,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AuraColors.obsidian,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AuraSpace.s1),
                Center(
                  child: Text('$endpoint', style: AuraType.metric),
                ),
                const SizedBox(height: AuraSpace.s2),
              ],
          ],
        ),
      ),
    );
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({
    required this.ring,
    required this.isWide,
    required this.locking,
    required this.onAccept,
  });

  final RingVm ring;
  final bool isWide;
  final bool locking;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AuraSpace.s2, 0, AuraSpace.s2, AuraSpace.s2),
      padding: const EdgeInsets.all(AuraSpace.s2),
      decoration: BoxDecoration(
        color: AuraColors.carbon,
        border:
            Border.all(color: AuraColors.slate, width: AuraStroke.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  ring.participants.map((p) => p.alias).join('  →  '),
                  style: AuraType.title,
                ),
              ),
              const SizedBox(width: AuraSpace.s2),
              Text(
                '${(ring.matchStrength * 100).toStringAsFixed(0)}%',
                style: AuraType.metricLarge,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.s1),
          // Weakest-hop strength as a 2 px stroke — the one place data
          // earns geometry.
          FractionallySizedBox(
            widthFactor: ring.matchStrength.clamp(0.0, 1.0),
            child: Container(
                height: AuraStroke.indicator, color: AuraColors.type),
          ),
          const SizedBox(height: AuraSpace.s2),
          for (final participant in ring.participants)
            Padding(
              padding: const EdgeInsets.only(bottom: AuraSpace.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      participant.isSelf ? 'YOU' : participant.alias,
                      style: participant.isSelf
                          ? AuraType.label
                              .copyWith(color: AuraColors.type)
                          : AuraType.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(participant.gives,
                        style: AuraType.bodyDim,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  // Locally derived trust from completed-ring history;
                  // silent at zero — no fabricated figures.
                  if (!participant.isSelf &&
                      participant.reliabilityScore > 0) ...[
                    const SizedBox(width: AuraSpace.s1),
                    Text('TRUST ${participant.reliabilityScore}',
                        style: AuraType.label),
                  ],
                ],
              ),
            ),
          const SizedBox(height: AuraSpace.s1),
          Row(
            children: [
              Text('${ring.hopCount}-PARTY LOOP', style: AuraType.label),
              if (ring.involvesSelf) ...[
                const SizedBox(width: AuraSpace.s2),
                Text('INCLUDES YOU',
                    style:
                        AuraType.label.copyWith(color: AuraColors.type)),
              ],
              const Spacer(),
              if (isWide)
                GestureDetector(
                  onTap: locking ? null : onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AuraSpace.s2,
                        vertical: AuraSpace.s1),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AuraColors.type,
                          width: AuraStroke.line),
                    ),
                    child: Text('ROUTE',
                        style: AuraType.label
                            .copyWith(color: AuraColors.type)),
                  ),
                )
              else
                Text('SWIPE → TO ROUTE', style: AuraType.label),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Module B — COMPUTE
// ---------------------------------------------------------------------

class _ComputePane extends StatelessWidget {
  const _ComputePane({
    required this.gate,
    required this.optedIn,
    required this.onToggle,
  });

  final SwarmComputeGate gate;
  final bool optedIn;
  final ValueChanged<bool> onToggle;

  static ({String word, String detail, Color color}) _describe(
    ComputeEligibility state,
  ) =>
      switch (state) {
        ComputeEligibility.eligible => (
            word: 'READY',
            detail: 'All hardware invariants verified. The worker may '
                'accept inference chunks.',
            color: AuraColors.emerald,
          ),
        ComputeEligibility.discharging => (
            word: 'ON BATTERY',
            detail: 'Connect external power. Compute never drains a '
                'battery.',
            color: AuraColors.amber,
          ),
        ComputeEligibility.overheating => (
            word: 'THERMAL BLOCK',
            detail: 'Battery at or above 37.5 °C. Work resumes when the '
                'device cools.',
            color: AuraColors.amber,
          ),
        ComputeEligibility.untrustedNetwork => (
            word: 'UNTRUSTED NETWORK',
            detail: 'Join a trusted Wi-Fi. Inference chunks never travel '
                'metered or unknown links.',
            color: AuraColors.amber,
          ),
        ComputeEligibility.indeterminate => (
            word: 'TELEMETRY UNKNOWN',
            detail: 'Hardware state cannot be verified — compute stays '
                'blocked (fail-closed).',
            color: AuraColors.slate,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ComputeEligibility>(
      valueListenable: gate.eligibility,
      builder: (context, eligibility, _) {
        final status = _describe(eligibility);

        return ListView(
          padding: const EdgeInsets.all(AuraSpace.s3),
          children: [
            // Hero status block: 2 px accent stroke + display word.
            Container(height: AuraStroke.indicator, color: status.color),
            const SizedBox(height: AuraSpace.s3),
            Text(optedIn ? status.word : 'OPTED OUT',
                style: AuraType.display),
            const SizedBox(height: AuraSpace.s1),
            Text(
              optedIn
                  ? status.detail
                  : 'This device contributes nothing to the swarm. '
                      'Telemetry polling is stopped.',
              style: AuraType.bodyDim,
            ),
            const SizedBox(height: AuraSpace.s4),

            // Opt-in toggle.
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AuraSpace.s2, vertical: AuraSpace.s1),
              decoration: BoxDecoration(
                border: Border.all(
                    color: AuraColors.slate, width: AuraStroke.line),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CONTRIBUTE NPU / GPU',
                            style: AuraType.label),
                        SizedBox(height: 4),
                        Text(
                          'Only while charging, cool, and on a trusted '
                          'network.',
                          style: AuraType.bodyDim,
                        ),
                      ],
                    ),
                  ),
                  Switch(value: optedIn, onChanged: onToggle),
                ],
              ),
            ),
            const SizedBox(height: AuraSpace.s4),

            // Telemetry readouts — bound to the RAW poll stream so
            // intra-state drift (34.1 °C → 35.5 °C) repaints every tick,
            // not only on eligibility transitions. Seeded from
            // lastSnapshot so tab entry never shows a blank frame.
            // Nulls render as em-dash, never as a fabricated number.
            if (optedIn) ...[
              const _SectionHeader(label: 'TELEMETRY', inset: false),
              const SizedBox(height: AuraSpace.s1),
              StreamBuilder<TelemetrySnapshot>(
                stream: gate.onTelemetryRaw,
                initialData: gate.lastSnapshot,
                builder: (context, telemetry) {
                  final live = telemetry.data;
                  return Column(
                    children: [
                      _telemetryRow(
                        'POWER',
                        switch (live?.isCharging) {
                          true => 'CHARGING',
                          false => 'ON BATTERY',
                          null => '—',
                        },
                      ),
                      _telemetryRow(
                        'BATTERY TEMP',
                        live?.batteryTemperatureCelsius == null
                            ? '—'
                            : '${live!.batteryTemperatureCelsius!.toStringAsFixed(1)} °C',
                      ),
                      _telemetryRow('WI-FI SSID', live?.wifiSsid ?? '—'),
                    ],
                  );
                },
              ),
            ],

            // Non-intrusive capability reminder for indeterminate.
            if (optedIn &&
                eligibility == ComputeEligibility.indeterminate) ...[
              const SizedBox(height: AuraSpace.s3),
              Container(
                padding: const EdgeInsets.all(AuraSpace.s2),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: AuraColors.amber,
                        width: AuraStroke.indicator),
                  ),
                ),
                child: const Text(
                  'Telemetry could not be read. Common causes: location '
                  'permission not granted (required by the OS to read the '
                  'Wi-Fi name), location services disabled, or a platform '
                  'without hardware sensors (web). The gate stays blocked '
                  'until readings are verifiable.',
                  style: AuraType.bodyDim,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _telemetryRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.s1),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AuraColors.hairline, width: AuraStroke.hair),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AuraType.label)),
          Text(value, style: AuraType.metric),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Module C — GRID
// ---------------------------------------------------------------------

class _GridPane extends StatelessWidget {
  const _GridPane({required this.intents, required this.isWide});

  final List<ResourceIntent> intents;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (intents.isEmpty) {
      return const _EmptyState(
        title: 'NO GRID NODES ON MESH',
        detail: 'Energy telemetry tiles appear here as adjacent microgrid '
            'nodes gossip surplus and demand. Layout is wired for the '
            'Modbus TCP / MQTT inverter gateway (Module C).',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AuraSpace.s2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 3 : 2,
        mainAxisSpacing: AuraSpace.s2,
        crossAxisSpacing: AuraSpace.s2,
        childAspectRatio: 1.4,
      ),
      itemCount: intents.length,
      itemBuilder: (context, index) => _EnergyTile(intent: intents[index]),
    );
  }
}

class _EnergyTile extends StatelessWidget {
  const _EnergyTile({required this.intent});

  final ResourceIntent intent;

  bool get _isSurplus => intent.direction == IntentDirection.offer;

  String get _age {
    final delta = DateTime.now().toUtc().difference(
          DateTime.fromMillisecondsSinceEpoch(intent.epochTimestamp,
              isUtc: true),
        );
    if (delta.inMinutes < 1) return 'NOW';
    if (delta.inHours < 1) return '${delta.inMinutes}M AGO';
    return '${delta.inHours}H AGO';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AuraSpace.s2),
      decoration: BoxDecoration(
        color: AuraColors.carbon,
        border:
            Border.all(color: AuraColors.slate, width: AuraStroke.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AuraStroke.indicator,
                height: 12,
                color:
                    _isSurplus ? AuraColors.emerald : AuraColors.amber,
              ),
              const SizedBox(width: AuraSpace.s1),
              Text(_isSurplus ? 'SURPLUS' : 'DEMAND',
                  style: AuraType.label),
            ],
          ),
          const Spacer(),
          Text('${intent.structuralQuantity}',
              style: AuraType.metricLarge),
          Text('WATT-HOURS', style: AuraType.label),
          const SizedBox(height: AuraSpace.s1),
          Text(
            '${intent.originNodeKey.substring(0, 8)}…  ·  $_age',
            style: AuraType.bodyDim,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared fragments
// ---------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.inset = true});

  final String label;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: inset
          ? const EdgeInsets.fromLTRB(
              AuraSpace.s2, AuraSpace.s2, AuraSpace.s2, AuraSpace.s1)
          : EdgeInsets.zero,
      child: Text(label, style: AuraType.label),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AuraSpace.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AuraType.label),
              const SizedBox(height: AuraSpace.s2),
              Text(detail,
                  textAlign: TextAlign.center, style: AuraType.bodyDim),
            ],
          ),
        ),
      ),
    );
  }
}
