// lib/ui/identity_gate.dart
//
// Second onboarding step (ROADMAP Phase 0): choose an alias and SEE the
// public key this device will be known by, before the mesh node boots.
// Sits between PermissionGate and the composition root's FutureBuilder,
// so bootstrap() — which reads the stored alias — cannot start early.
//
// The key is loaded through main.dart's loadOrCreateSigner(), the same
// idempotent custody path bootstrap uses: no duplicated key logic, the
// seed never leaves platform secure storage.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/ed25519_signer.dart';
import 'app_theme.dart';

class IdentityGate extends StatefulWidget {
  const IdentityGate({
    super.key,
    required this.aliasStorageKey,
    required this.loadSigner,
    required this.builder,
  });

  final String aliasStorageKey;

  /// main.loadOrCreateSigner — injected so this widget stays free of
  /// composition-root imports (view → root would invert the layering).
  final Future<Ed25519IdentitySigner> Function() loadSigner;

  final WidgetBuilder builder;

  @override
  State<IdentityGate> createState() => _IdentityGateState();
}

class _IdentityGateState extends State<IdentityGate> {
  static const _storage = FlutterSecureStorage();
  static const int _maxAliasLength = 24;

  final TextEditingController _alias = TextEditingController();

  /// null = still checking storage; afterwards the gate either passes
  /// (true) or shows the form (false).
  bool? _aliasStored;
  String? _publicKeyHex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final stored = await _storage.read(key: widget.aliasStorageKey);
    if (!mounted) return;
    if (stored != null && stored.trim().isNotEmpty) {
      setState(() => _aliasStored = true);
      return;
    }
    setState(() => _aliasStored = false);
    // Load (or mint) the identity so the user sees their real key and
    // a suggestion derived from it — bootstrap will read the same seed.
    final signer = await widget.loadSigner();
    if (!mounted) return;
    setState(() {
      _publicKeyHex = signer.publicKeyHex;
      if (_alias.text.isEmpty) {
        _alias.text = 'node-${signer.publicKeyHex.substring(0, 6)}';
      }
    });
  }

  Future<void> _save() async {
    final alias = _alias.text.trim();
    if (alias.isEmpty || _saving) return;
    setState(() => _saving = true);
    await _storage.write(key: widget.aliasStorageKey, value: alias);
    if (!mounted) return;
    setState(() => _aliasStored = true);
  }

  /// 64 hex chars as 4 groups per line — scannable, not a wall.
  String _formatKey(String hex) {
    final groups = <String>[
      for (var i = 0; i < hex.length; i += 8) hex.substring(i, i + 8),
    ];
    final lines = <String>[
      for (var i = 0; i < groups.length; i += 4)
        groups.skip(i).take(4).join(' '),
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (_aliasStored == true) return widget.builder(context);

    return Scaffold(
      backgroundColor: AuraColors.obsidian,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AuraSpace.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('MESH IDENTITY', style: AuraType.label),
              const SizedBox(height: AuraSpace.s2),
              const Text(
                'This device signs everything it publishes with a key '
                'that never leaves it. Peers will know you by the alias '
                'below — pick one, or keep the generated name.',
                style: AuraType.bodyDim,
              ),
              const SizedBox(height: AuraSpace.s3),
              const Text('PUBLIC KEY', style: AuraType.label),
              const SizedBox(height: AuraSpace.s1),
              if (_publicKeyHex == null)
                const Text('GENERATING…', style: AuraType.label)
              else
                Text(
                  _formatKey(_publicKeyHex!),
                  style: AuraType.metric.copyWith(height: 1.5),
                ),
              const SizedBox(height: AuraSpace.s3),
              const Text('ALIAS', style: AuraType.label),
              const SizedBox(height: AuraSpace.s1),
              TextField(
                controller: _alias,
                enabled: !_saving,
                cursorColor: AuraColors.type,
                cursorWidth: 2,
                style: AuraType.input,
                maxLength: _maxAliasLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxAliasLength),
                ],
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: AuraColors.slate, width: AuraStroke.line),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: AuraColors.type, width: AuraStroke.line),
                  ),
                ),
              ),
              const SizedBox(height: AuraSpace.s4),
              GestureDetector(
                onTap: _saving || _publicKeyHex == null ? null : _save,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: AuraSpace.s2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _publicKeyHex == null
                          ? AuraColors.hairline
                          : AuraColors.slate,
                      width: AuraStroke.line,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _saving ? 'SAVING…' : 'ENTER THE MESH',
                      style: AuraType.label
                          .copyWith(color: AuraColors.type),
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
