# Aura OmniMesh v1.0.0 — FluidMesh

Local-first peer-to-peer barter. **Zero servers, no accounts, no tracking.**
Your intents live on your device and sync directly between nearby peers; nothing
is uploaded to a company.

---

## English

### What this is
Aura OmniMesh finds **barter rings** — closed loops where what you offer is what
someone else needs, around a cycle that closes back to you — across a local mesh
of devices, with no backend. Matching runs **on your device** with a multilingual
neural model, so "offer: Dart tutoring" and "need: help with Flutter" match even
across languages, and nothing you type leaves your phone.

### Highlights
- **Serverless mesh** — devices gossip a signed CRDT operation log; the log is the
  source of truth, and every operation is Ed25519-signed. No central server exists
  to seize, subpoena, or shut down.
- **On-device multilingual matching** — ONNX `paraphrase-multilingual-MiniLM-L12`
  (int8, vocabulary-trimmed), runs locally on Android and in the browser (WASM).
- **Closed-loop exchange flow** — discover a ring → lock your hop → all hops
  confirmed → mark fulfilled, with local notifications. Reputation is earned from
  your signed history of completed rings.
- **Private by construction** — no analytics, no ad IDs, no cloud. See the privacy
  policy in `docs/store/`.

### Install (Android)
1. Download **`app-release.apk`** from the assets below.
2. Open it; Android will ask to allow installs from this source — approve for your
   browser/file manager.
3. On first launch, pick an alias and you're on the mesh.

Signed with the project release key. This is an early public build — see
limitations below.

### Web light client
A browser PWA can join as a **Light Client** when a Core Node is reachable on the
LAN. It fetches the ML model at runtime from this release
(`minilm_multilingual_trimmed_v2.onnx`), so that asset must stay attached here.

### Known limitations (honest notes)
- **Android in this release.** iOS is built for but not shipped yet (needs a Mac
  build/signing pass; App Store review notes are prepared).
- **Direct radio peering is still in field testing.** Device-to-device sync is
  verified on-device and over the LAN WebSocket bridge; over-the-air Nearby
  peering across separate phones is the next thing being tested in the wild —
  reports welcome.
- **iOS and Android do not peer directly over the air** (Multipeer vs Nearby);
  cross-OS traffic goes through a device acting as a LAN bridge. This is by design.
- **Web is an ephemeral Light Client** — it holds no durable store yet.

---

## Русский

### Что это
Aura OmniMesh находит **бартерные кольца** — замкнутые цепочки, где то, что вы
предлагаете, нужно другому, и круг замыкается обратно на вас — в локальной сети
устройств, без сервера. Мэтчинг работает **на вашем устройстве** мультиязычной
нейросетью: «offer: репетитор Dart» и «need: помочь с Flutter» находят друг друга
даже на разных языках, и введённый текст не покидает телефон.

### Главное
- **Сеть без серверов** — устройства обмениваются подписанным CRDT-логом операций;
  лог — источник истины, каждая операция подписана Ed25519. Центрального сервера,
  который можно изъять или отключить, просто нет.
- **Мультиязычный мэтчинг на устройстве** — ONNX
  `paraphrase-multilingual-MiniLM-L12` (int8, урезанный словарь), локально на
  Android и в браузере (WASM).
- **Замкнутый цикл обмена** — нашли кольцо → залочили свой шаг → все шаги
  подтверждены → отметили выполнение, с локальными уведомлениями. Репутация
  растёт из вашей подписанной истории закрытых колец.
- **Приватность по устройству** — ни аналитики, ни рекламных ID, ни облака.
  Политика приватности — в `docs/store/`.

### Установка (Android)
1. Скачайте **`app-release.apk`** из ассетов ниже.
2. Откройте; Android попросит разрешить установку из этого источника — разрешите
   для браузера/файлового менеджера.
3. При первом запуске выберите алиас — и вы в сети.

Подписано релизным ключом проекта. Это ранняя публичная сборка — см. ограничения.

### Ограничения (честно)
- **В этом релизе — Android.** iOS собирается, но пока не выпущен (нужен билд/подпись
  на Mac; тексты для App Review готовы).
- **Прямое радио-соединение ещё проходит полевые тесты.** Синхронизация между
  устройствами проверена на устройстве и через LAN-мост (WebSocket); эфирное
  Nearby-соединение между отдельными телефонами — следующее в очереди на проверку
  «в поле». Отчёты приветствуются.
- **iOS и Android не соединяются напрямую по воздуху** (Multipeer против Nearby);
  межплатформенный трафик идёт через устройство-мост в LAN. Так задумано.
- **Веб — эфемерный Light Client**, устойчивого хранилища у него пока нет.

---

_Build: Flutter 3.44.6 · version 1.0.0+1 · 112-test suite green · `flutter analyze`
clean._
