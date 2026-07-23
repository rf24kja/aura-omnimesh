# Module C — VoltMesh (design)

Status: **design + register-decode primitive**. Modules A (barter) and B
(compute) are done; this is the energy module. As with B, the rule is **reuse
the audited Module A machinery** — energy readings are `ResourceIntent` rows
with the frozen `AllocationCategory.energyTelemetry`, and the GRID tab already
reads them (`readIntentsByCategory(energyTelemetry)`).

VoltMesh turns a phone into a **local energy cockpit**: it reads a solar
inverter / battery over Modbus TCP or MQTT on the LAN, shows live production
and state-of-charge, and (opt-in, gated) can toggle a local relay. Zero cloud —
the inverter and relay are on the same Wi-Fi, exactly like the mesh.

---

## 1. Read pipeline

```
Modbus TCP / MQTT (LAN)  ->  decode registers  ->  EnergyReading
   ->  energy_telemetry ResourceIntent row  ->  GRID tab
```

- Field mapping on `ResourceIntent`: `rawTextPayload` = metric name
  ("pv_power", "battery_soc", …), `structuralQuantity` = the integer value
  (watt-hours / watts / percent per the metric), `epochTimestamp` = reading
  time, `vectorData` = zeros (the 384-dim assert still applies; energy rows
  are not semantically matched), `allocationCategory` = energyTelemetry.
- `lib/energy/modbus_registers.dart` (this commit) is the pure, deterministic
  decoder: a block of 16-bit Modbus registers + a `RegisterSpec` map → typed
  `EnergyReading`s. It is the only piece that is unit-testable with no
  hardware, and it is where every device-specific quirk (16/32-bit, signedness,
  word order, scale) is captured as data, not code.

---

## 2. SAFETY — read-only by default; actuation is gated

VoltMesh can **switch a relay** (Shelly via local HTTP). That is a physical
action, so it follows the project's fail-closed ethos AND ordinary
consequential-action caution:

- **Read paths are always safe** and run automatically. Control paths do not.
- **No automatic actuation, ever.** A relay only changes on an explicit,
  per-action user confirmation in the UI — never on a schedule, a threshold, or
  a mesh message. There is no "auto" mode in v1.
- **Fail-closed readings.** An unreadable register / lost inverter link renders
  as an em-dash, never a fabricated number (same rule as SwarmComputeGate
  telemetry). A control command whose result cannot be confirmed is reported as
  failed, not assumed done.
- Mesh messages never trigger control. A neighbor cannot flip your relay.

---

## 3. Persistence & gossip — an explicit design decision

Energy telemetry is HIGH-FREQUENCY (seconds), and the CRDT log is durable and
gossiped. Publishing every reading as a signed op would bloat the shared log.
Options (to settle before phase 4):

- **(recommended) Local + downsampled.** Poll fast for the live UI, but persist
  a signed energy op only on a modest cadence (e.g. ≤ 1/min per metric) or a
  meaningful change. These MAY gossip so a microgrid can see aggregate
  production (the "VoltMesh" vision), but the low rate keeps the log bounded.
- **Local-only.** Energy rows never leave the device (a private dashboard).
  Requires an append+materialize path that does not gossip — a small engine
  addition — since today `publishLocalDeltas` always gossips.

Either way the materializer stays the sole row-writer (invariant 2): energy
rows are folded from signed `create_intent` ops with the energyTelemetry
category, never upserted directly.

---

## 4. Phased plan

1. **Modbus register decoder** (pure, deterministic). *Done this commit, with
   tests over synthetic register blocks.*
2. **Register maps** for representative inverters (Deye/Growatt) as data — a
   sample map ships now; authoritative maps are per-firmware and community-
   sourced.
3. **Transport clients** — Modbus TCP (`package:modbus_client` or a minimal
   socket reader) and MQTT (`package:mqtt_client`). Needs real hardware or a
   Modbus simulator to verify.
4. **Reading → energy row pipeline** — apply the §3 decision; downsample and
   publish signed energy ops, materialized into GRID-tab rows.
5. **Shelly relay control** — local HTTP, behind the §2 confirmation gate.
   Needs a relay to verify.
6. **GRID-tab wiring** — the tab already renders energyTelemetry rows; add live
   metric tiles + the (gated) relay control.

Steps 1-2 and 4's op-shaping are off-device testable; 3, 5, and on-device
polish need hardware.

---

## 5. Invariants this design must not break

- **2** — energy rows are materialized from signed ops, never upserted around
  the log.
- **4** — fail-closed: unreadable inverter → em-dash, never a guess; an
  unconfirmed control command is a failure, not a success.
- **5** — energyTelemetry is a frozen category; no renames.
- Consequential-action caution — relay actuation is explicit, confirmed, and
  never automatic or mesh-triggered.
