# HANDOFF PROMPT ДЛЯ CLAUDE CODE
Скопируй всё, что ниже разделителя, и вставь первым сообщением в Claude Code,
запущенный в корне папки `aura_omnimesh/`.

---

<role>
You are the build engineer for Aura OmniMesh — a local-first P2P exchange
protocol on Flutter. The full architecture (15 Dart files + 4 native platform
files) was designed and written externally and is waiting in `_incoming/`.
Your job is NOT to design or refactor. Your job is: scaffold the project,
place every file where its header says it belongs, configure the toolchain,
and drive the codebase to Phase 0 acceptance.
</role>

<inputs>
Everything sits in `_incoming/`:
- 14 Dart files — each begins with a comment `// lib/<path>.dart` stating its
  exact destination inside lib/.
- `TelemetryChannel.kt`, `NearbyTransportChannel.kt` — headers state their
  android/ destination (package com.aura.omnimesh).
- `TelemetryChannel.swift`, `MultipeerTransportChannel.swift` — ios/Runner/.
- `PLATFORM_SETUP.md` — MainActivity/AppDelegate registration code, manifest
  permissions, Info.plist keys, entitlements, gradle dependency. Follow it
  verbatim; it is the platform-integration source of truth.
- `CLAUDE.md` — move to repo root FIRST, before touching any code. It contains
  the architectural invariants you must not break. Read it fully.
- `ROADMAP.md` — move to repo root. Context only; do not start later phases.
- `index.html` — marketing site; move to `website/index.html`, otherwise ignore.
</inputs>

<environment_setup>
1. Verify toolchain: `flutter doctor -v`. If Flutter is missing, install the
   latest stable channel for this OS and re-run doctor. Report unresolvable
   doctor issues (e.g., no Xcode on non-macOS) instead of silently skipping —
   on a non-Mac machine, iOS work is explicitly OUT of scope for this session;
   Android + web are in scope.
2. Scaffold IN PLACE so the Android package matches the Kotlin sources:
   `flutter create --org com.aura --project-name omnimesh --platforms android,ios,web .`
   The resulting applicationId / package MUST be `com.aura.omnimesh`. Verify it
   in android/app/build.gradle and in the generated MainActivity path before
   proceeding; fix the org, never the .kt package lines.
3. `git init` (if absent), commit the pristine scaffold as
   `chore: flutter scaffold`, then commit after each subsequent step —
   granular history is required for reviewing your changes.
</environment_setup>

<placement_and_config>
4. Move every `_incoming/` file to the destination named in its own header.
   Replace the generated lib/main.dart, MainActivity.kt, AppDelegate.swift
   with the versions dictated by the sources + PLATFORM_SETUP.md.
5. pubspec.yaml dependencies (resolve latest compatible within these majors):
   isar ^3.1.0, isar_flutter_libs ^3.1.0, path_provider, cryptography ^2.7.0,
   web_socket_channel ^2.4.0, flutter_secure_storage ^9.0.0,
   permission_handler. dev: isar_generator ^3.1.0, build_runner,
   flutter_lints.
6. Apply PLATFORM_SETUP.md sections 1–2 exactly: manifest permissions, gradle
   Nearby dependency, Info.plist keys, entitlements, channel registration.
7. `dart run build_runner build --delete-conflicting-outputs`.
</placement_and_config>

<phase0_execution>
8. Iterate `flutter analyze` → fix → repeat until ZERO errors and ZERO
   warnings. Expected fix zones are listed in CLAUDE.md under "known-fragile
   areas" (Isar codegen names, Nearby/Multipeer API signatures). Fix call
   sites to match real APIs; do not restructure modules.
9. Build: `flutter build apk --debug` and `flutter build web`. On macOS also
   `flutter build ios --debug --no-codesign`. Fix until all in-scope targets
   build.
10. Run on whatever device/emulator is available and confirm: app boots,
    onboarding gap is EXPECTED (permissions flow is Phase 0 work — implement a
    minimal permission-request screen per ROADMAP Phase 0 if boot is blocked
    by missing runtime permissions, nothing more).
</phase0_execution>

<hard_constraints>
- CLAUDE.md invariants override any refactoring instinct. In particular: never
  duplicate signature preimages, never add intent-row writers beside the
  materializer, never replace FNV-1a with String.hashCode, never rename enum
  wire values, never use ByteData.setInt64.
- Compile fixes = smallest change that satisfies the real API. If a fix seems
  to require architectural change, STOP and ask with a concrete diff proposal.
- No new dependencies beyond the list above without asking.
- Do not start Phase 1+ features (QR pairing, ONNX, ring-confirmation UX).
- Never delete `_incoming/` until every file is confirmed moved (then remove it).
</hard_constraints>

<acceptance_and_report>
Done means: `flutter analyze` clean · `flutter test` passes (add a smoke test
that pumps the app root if none exists) · in-scope targets build · app boots on
a device/emulator with the status strip rendered.

Final message format:
1. Environment summary (flutter doctor result, platforms in scope).
2. Table: every _incoming file → final path.
3. Complete list of code changes you made to achieve compilation, each with a
   one-line justification (this list will be reviewed against the invariants).
4. Build/run evidence (command outputs).
5. Open issues blocking Phase 1, ranked.
</acceptance_and_report>
