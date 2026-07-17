# App Review Notes (Apple) — черновик для App Store Connect

Скопировать в поле "Notes" при сабмите. Multipeer Connectivity и Local
Network — частые триггеры вопросов ревью; ROADMAP требует проговорить
офлайн-природу приложения явно.

---

Aura OmniMesh is a fully offline, serverless peer-to-peer barter
discovery app. There is NO backend: devices exchange cryptographically
signed records directly over Multipeer Connectivity (iOS↔iOS) and a
local-network WebSocket bridge (cross-platform, port 7411). This is why
the app requests:

- **Local Network permission + Bonjour services** (`_aura-omnimesh._tcp/_udp`):
  used to discover and connect to nearby devices running the app on the
  same Wi-Fi. No internet servers are contacted.
- **Location (When In Use)**: iOS requires location permission for
  `NEHotspotNetwork.fetchCurrent` — the app reads ONLY the current
  Wi-Fi network NAME (SSID) to let users restrict background compute
  sharing to trusted networks. GPS coordinates are never read; there is
  no map, no geotagging, no location storage.
- **Access Wi-Fi Information entitlement**: same purpose as above.

How to test without a second device: launch the app, grant the
requested permissions, publish an offer via the top command line (e.g.
"offer: guitar lessons"). The intent appears under MY INTENTS; the
status strip at the bottom shows live mesh state. With two iPhones on
the same Wi-Fi, publishing complementary offers/needs on each device
surfaces a barter ring card on both within seconds — all without any
internet connectivity (airplane mode + Wi-Fi is sufficient).

The app contains no ads, no analytics, no third-party tracking, no
account system, and transmits nothing to the developer. The bundled
~76 MB ML model performs multilingual semantic matching entirely
on-device.

Demo video: [приложить перед сабмитом — офлайн-замыкание кольца на
двух устройствах в авиарежиме]
