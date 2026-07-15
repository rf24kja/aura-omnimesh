# CLAUDE.md — Aura OmniMesh

Local-first P2P exchange protocol. Flutter (iOS/Android/Web PWA), zero servers.
Full plan: ROADMAP.md. Current phase: **Phase 0 — make everything compile.**

## Commands
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after ANY schema change
dart run tool/fix_web_ids.dart   # ALWAYS run right after codegen: rewrites
                                 # isar 3.1.0+1 schema-id literals that dart2js
                                 # rejects (see tool/fix_web_ids.dart header)
flutter analyze          # must be zero errors AND zero warnings
flutter test
flutter run -d <device>
```

## File map (headers in each file state the intended path)
```
lib/domain/domain_models.dart        # Isar collections + enums (wire values are FROZEN)
lib/services/services.dart           # ALL abstract contracts (repo, transport, signer, applier)
lib/crypto/ed25519_signer.dart       # canonical preimages + signer — the ONLY crypto source
lib/data/isar_mesh_repository.dart
lib/transport/hybrid_transport_service.dart   # native + web light client
lib/transport/bridge_server.dart     # Core Node WebSocket bridge (dart:io, NOT on web)
lib/engine/mesh_sync_engine.dart     # gossip, anti-entropy, serialized task lane
lib/engine/crdt_materializer.dart    # log fold -> intent rows (sole writer of intents)
lib/matching/ring_matcher.dart       # canonical-start DFS, deterministic ranking
lib/compute/swarm_compute_gate.dart  # hardware eligibility, fail-closed
lib/ui/app_theme.dart | dashboard_view.dart | mesh_ui_adapter.dart
lib/main.dart                        # composition root (in-memory repo + hashing embeddings live here)
android/.../TelemetryChannel.kt, NearbyTransportChannel.kt
ios/Runner/TelemetryChannel.swift, MultipeerTransportChannel.swift
PLATFORM_SETUP.md                    # manifests, plists, entitlements, registration
```

## Invariants — do not break, do not "improve"
1. **Signature preimages are canonical and single-sourced.** CRDT ops:
   `utf8(payloadJson) || clock as 8 LE bytes` — only `crdtSignaturePreimage()`
   in ed25519_signer.dart. Bridge handshake:
   `utf8("aura-omnimesh/bridge-hello/v1") || 0x00 || nonce` — only
   `handshakeChallengePreimage()`. A one-byte drift silently invalidates every
   signature on the mesh. Never inline a second definition.
2. **The CRDT log is the source of truth; intent rows are a materialized view.**
   `CrdtMaterializer` is the ONLY steady-state writer of ResourceIntent rows.
   Never add a direct upsert next to a published op — that is how views diverge.
3. **Determinism is a correctness property, not style.** Ring ranking
   (`BarterRing.rank`), causal order (`causalCompare` with UUID tiebreak), and
   embeddings (FNV-1a, NOT String.hashCode) must produce identical results on
   every device. Any change here needs a cross-device determinism test.
4. **Fail-closed everywhere.** Unreadable telemetry → `indeterminate`, never a
   guessed value. Unverified bridge → terminate, never retry the endpoint.
   Nulls render as em-dash in UI, never as fabricated numbers.
5. **Enum wire values are frozen** ('peer_exchange', 'locked_in_loop', …) —
   they live in persisted rows and on the wire. Add values; never rename.
6. **Ed25519 seed never leaves Dart** (flutter_secure_storage). No native code
   may receive the private key — that is why bridge_server.dart is Dart.
7. **Authentication ≠ authorization**: a valid signature under the wrong key is
   still a rejection. Only an intent's owner authors its status transitions.
8. **ByteData.setInt64 is forbidden** (throws under dart2js). Manual LE loops only.
9. **Design tokens only** (app_theme.dart). No raw hex, no border-radius, color
   appears exclusively as 1–2 px indicator strokes (emerald/amber).

## Known-fragile areas (expect compile fixes here first)
- Isar codegen names (`nodeIdentitys`, `getByIntentUuid`, `putByIntentUuid`,
  composite where-clauses) — written from memory, verify against generated code.
- Nearby Connections / Multipeer API signatures in the .kt/.swift files.
- `List<float>` (Isar float32 typedef) on ResourceIntent.vectorData — keep it;
  do not "fix" to List<double> storage.

## Platform facts
- Multipeer (iOS) and Nearby (Android) do NOT interoperate over the air.
  Cross-OS traffic goes through the LAN WebSocket bridge. Not a bug.
- iOS SSID requires location permission + wifi-info entitlement; iOS battery
  temperature does not exist — thermalState proxy in TelemetryChannel.swift is
  deliberate and documented.
- Web target: in-memory repository (ephemeral light client) until Drift-wasm.

## Phase 0 definition of done
`flutter analyze` clean · all three targets build · app boots on a physical
iPhone and Android · status strip live · telemetry rows show real values.
