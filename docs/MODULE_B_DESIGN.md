# Module B — SwarmCompute (design)

Status: **design + foundational primitive**. Module A (FluidMesh) is v1.0 and
frozen; this is the post-release build-out of the compute module. Nothing here
changes Module A behavior.

The guiding rule: **reuse the audited Module A machinery, do not reinvent it.**
The signed CRDT log, `causalCompare` ordering, `CrdtMaterializer`, Ed25519
signing, and determinism are already proven and tested. Compute rides on top of
them exactly the way energy telemetry (Module C) already does — as
`ResourceIntent` rows carried by the same log and distinguished by
`AllocationCategory`.

---

## 1. What SwarmCompute is

A device with spare, *safe* capacity (charging, cool, on a trusted network —
gated by the existing `SwarmComputeGate`) runs small inference tasks that a
nearby device offers, and returns a **verifiable** result. No servers, no
money, no accounts — the same trust model as barter: authenticity by signature,
correctness by re-execution.

v1 scope: **deterministic edge inference** (the same ONNX MiniLM embedding the
mesh already runs). Deterministic is the key word — it is what makes results
checkable without a trusted verifier (see §4).

---

## 2. It rides the existing log (no new transport, no new crypto)

- Compute artifacts are `ResourceIntent` rows with
  `AllocationCategory.computeAllocation` — the frozen wire value already in
  `domain_models.dart`. Module C already proves this pattern works
  (`readIntentsByCategory(energyTelemetry)`).
- They travel as ordinary signed CRDT operations over the same
  `MeshSyncEngine` gossip / anti-entropy. No new frames.
- They are materialized by the same `CrdtMaterializer` fold, which already
  enforces signature (authentication) and ownership (authorization,
  invariant 7). New op names are **added** to `CrdtOps` — never renamed
  (invariant 5).

### New CRDT ops (additive)

| op wire value | author | meaning |
|---|---|---|
| `compute_task_offer` | requester | "compute embedding of THIS text; result must hash to a value I can re-check" |
| `compute_task_claim` | worker | "I (gated `eligible`) am taking this task" — deterministic single-claimer by smallest key, mirroring the Nearby initiator rule |
| `compute_task_result` | worker | carries the **output digest** + the worker's signature (proof-of-computation) |
| `compute_task_withdraw` | requester | cancels an unclaimed/unfinished task |

Lifecycle (a state machine folded from the log, exactly like intent status):
`offered → claimed → completed`, with `withdrawn` absorbing, same as
`IntentStatus`. Authorization: only the requester may offer/withdraw its task;
only the claiming worker may post that task's result. A valid signature under
the wrong key is still rejected — the materializer already does this.

---

## 3. Eligibility gating (already built)

`SwarmComputeGate` fail-closes to `indeterminate` and only reports `eligible`
when charging **and** cool (< 37.5 °C) **and** on a trusted SSID — all three
positively verified (audited, `test/compute_gate_test.dart`). A worker MUST NOT
author a `compute_task_claim` unless the gate currently reads `eligible`, and
MUST abandon in-flight work if the gate leaves `eligible` (thermal/‌power/‌network
change). The gate is the hard safety interlock; compute never cooks a stranger's
battery.

---

## 4. Proof-of-computation (the one new primitive)

"Proof of computation = signature of the output hash" (ROADMAP §5).

- The worker computes the result `R` (an embedding vector), serializes it
  **canonically and deterministically**, and takes `SHA-256` → the *result
  digest*.
- The `compute_task_result` op payload carries `taskId` + `outputDigest`, and
  is Ed25519-signed by the worker via the existing `crdtSignaturePreimage`
  (no second signing scheme — invariant 1).

What this proves, and what it does not:

- **Authenticity** (cheap, universal): the signature binds *this worker's key*
  to *this claimed digest*. Nobody can forge a result under another worker's
  key — the materializer verifies it like any op.
- **Correctness** (via determinism, invariant 3): because the task is
  deterministic (fixed model + fixed input → identical output on every device),
  the requester — or any peer — re-runs it locally and confirms the digest
  matches. A wrong or fabricated result fails the re-check and is discarded;
  the worker's `reliabilityScore` (already computed from signed history) can
  fold in compute honesty later.

Non-goals for v1 (documented, not hidden): no defense against a worker that
simply *doesn't* answer (that is availability, handled by re-offering to
another eligible peer), and no zero-knowledge / trusted-execution proof — v1
correctness rests entirely on the task being deterministic and cheap to
re-check.

`lib/compute/proof_of_computation.dart` (this commit) provides the canonical
digest + verify helpers; it is the only genuinely new cryptographic surface and
is unit-tested for determinism and tamper-rejection.

---

## 5. Phased build plan

1. **Proof-of-computation primitive** — canonical result digest + verify
   (SHA-256, deterministic). *Done in this commit, with tests.*
2. **Domain + ops** — `computeAllocation` task fields on the compute
   `ResourceIntent` (payload text = the input), the four `CrdtOps` above, and
   materialization of the `offered → claimed → completed → withdrawn` state
   machine. Mirror the intent lifecycle tests one-for-one.
3. **Worker** — subscribe to `SwarmComputeGate.onEligibilityChanged`; while
   `eligible`, claim one offered task, run the existing `EdgeInferenceService`,
   post a signed result; abandon on de-eligibility.
4. **Requester + verify** — offer a task, collect the result, re-run locally,
   confirm the digest, surface it.
5. **COMPUTE-tab queue UI** — the tab is already a telemetry cockpit; add the
   task queue (offered / claimed / completed) beside it.

Each step is independently testable off-device (the gate, the fold, the digest,
the deterministic embedding are all pure) — no phone required until step 5's
on-device polish.

---

## 6. Invariants this design must not break

- **1** — one signing preimage (`crdtSignaturePreimage`); the result digest is
  *inside* the signed payload, not a second signature scheme.
- **2** — the log is the source of truth; compute rows are materialized by the
  sole writer (`CrdtMaterializer`).
- **3** — determinism is what makes results checkable; the canonical digest
  must be byte-identical on every device.
- **4** — fail-closed: no claim unless `eligible`; unreadable state blocks work.
- **5** — enum wire values frozen; compute ops are *added*.
- **7** — auth ≠ authz: only the requester offers/withdraws, only the claiming
  worker results.
