# Security Policy

## Reporting a vulnerability

Please report security issues **privately**, not as a public GitHub issue.

- Email **rf24krsk@gmail.com** with subject `SECURITY: aura-omnimesh`.
- Include what you found, how to reproduce it, and the impact you believe it has.
- If you have a fix in mind, say so — but do not open a public PR that reveals the
  flaw before it is addressed.

This is a solo-maintained, local-first project; expect an acknowledgement within a
few days and a good-faith effort to fix and disclose. Please give reasonable time
before public disclosure. _(По-русски тоже можно — пишите на тот же адрес.)_

---

## What the security model actually is

Aura OmniMesh has **no server, no accounts, and no central authority**. There is
nothing to log into and nothing to breach centrally. Security is enforced
**per-operation and on-device**, so the transport (Bluetooth/Nearby radios, the LAN
WebSocket bridge) is treated as **fully untrusted** — an attacker who controls the
network still cannot forge, authorize, or tamper with an operation.

The whole system rests on a small set of invariants (see `CLAUDE.md`). Each one is
a security property with a test that locks it:

| Trust boundary | Threat | Defense | Enforced in | Locked by |
|---|---|---|---|---|
| Peer → CRDT log | Forged / tampered operations | Every operation is Ed25519-signed over a **canonical preimage**; the materializer verifies before applying | `crypto/ed25519_signer.dart`, `engine/crdt_materializer.dart` | `test/ed25519_signer_test.dart`, `test/crdt_materializer_test.dart` |
| Peer → intent status | Moving **someone else's** intent with a validly-signed op | Authentication ≠ authorization: only an intent's owner may author its transitions; a valid signature under the wrong key is still rejected | `crdt_materializer.dart` | `test/crdt_materializer_test.dart` |
| Peer → wire codec | Malformed frames crashing or smuggling values | Strict decode: missing/wrong-typed fields throw; unknown fields ignored; wire-supplied `reliabilityScore` is **discarded to 0** (no self-inflated trust) | `transport/hybrid_transport_service.dart` | `test/wire_codec_test.dart` |
| Rogue LAN bridge | Impersonating the Core Node | Bridge **proves possession** of its advertised key by signing a client nonce (`handshakeChallengePreimage`) before any sync; an ungreeted socket receives nothing | `transport/bridge_server.dart` | `test/bridge_sync_test.dart` |
| Native telemetry → compute gate | Guessing "safe" and cooking a battery | Fail-closed: unreadable / wrong-typed / errored telemetry → `indeterminate`; work is granted only when charging + cool + trusted-SSID are **all positively verified** | `compute/swarm_compute_gate.dart` | `test/compute_gate_test.dart` |
| Duplicate/replayed deltas | Echo storms, re-materialization churn | Idempotency is the loop breaker: a delta already held is never re-gossiped or re-applied | `engine/mesh_sync_engine.dart` | `test/mesh_sync_engine_test.dart` |
| Cross-device divergence | Two devices computing different results | Determinism as correctness: canonical signature preimages, `causalCompare` total order, FNV-1a embeddings | `ed25519_signer.dart`, `matching/ring_matcher.dart` | `test/determinism_test.dart` |

### Key custody
Your identity **is** a 32-byte Ed25519 seed. It is generated from the platform
CSPRNG and stored **only** in platform secure storage (iOS Keychain / Android
Keystore via `flutter_secure_storage`) — never in a plain file, never in logs, and
**it never leaves Dart**; no native channel receives the private key (this is why
the bridge server is written in Dart). The seed is the whole portable identity:
lose it and you lose your identity and its earned reputation; leak it and someone
can sign as you. Signatures are deterministic (RFC 8032), so the same seed produces
identical signatures on every device.

---

## What is explicitly out of scope

Being honest about non-goals is part of the security posture:

- **Confidentiality of intents.** Intents are public barter offers by design — the
  mesh is a shared board. There is no end-to-end encryption of intent content, and
  the LAN bridge is plaintext `ws://`. What signatures give you is **integrity and
  authenticity**, not secrecy. Do not put private data in an intent's text.
- **Anti-spam / Sybil resistance.** Anyone can generate an identity and sign their
  own intents; the protocol does not yet rate-limit or gate identity creation.
  Reputation is earned from completed rings, not a trust root.
- **Availability under a hostile network.** A peer can refuse to relay, and radios
  can be jammed. The design is partition-tolerant (store-and-forward, anti-entropy
  on reconnect), but it cannot force delivery through an adversary who controls the
  medium.
- **Compromised endpoints.** If the device OS or secure storage is compromised
  (rooted/jailbroken with the keystore extracted), the seed can be stolen — that is
  outside what an app can defend.
- **iOS.** Not yet shipped; the iOS build path is prepared but unaudited on device.

## Verifying an Android build

The APK published on the releases page is signed with the project release
key. Because it is installed outside Google Play, verify the signing
certificate before trusting a download — this is what proves the file came
from this project and was not tampered with in transit.

Run, against the file you downloaded:

```
apksigner verify --print-certs app-release.apk
```

and confirm the SHA-256 digest matches:

```
Signer #1 certificate DN:     CN=Aura OmniMesh, OU=Development, O=Aura OmniMesh
Signer #1 certificate SHA-256: b5af06c679460f9424d0fc14de46ed0b686c58ed96d359cbcb9503c07ad85eab
Signer #1 certificate SHA-1:   1bd152fbda524bb6ed4aa841fcdbb3d9b78dcd44
```

A mismatch means the build is not ours — do not install it. (The certificate
carries a development Organizational Unit; the key itself is the release key
and is what matters for continuity across updates.)

## Supported versions

Pre-1.0/early-1.0. Only the latest `main` and the most recent published release
receive security fixes.
