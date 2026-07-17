# Aura OmniMesh — Privacy Policy / Политика конфиденциальности

_Last updated / Обновлено: 2026-07_

## English

**The short version: your data never leaves your device unless you
explicitly publish it to nearby peers. We run no servers and collect
nothing.**

- **No accounts.** Your identity is an Ed25519 key pair generated on
  your device and stored in the platform secure enclave
  (Keychain / Android Keystore). We never see it.
- **No servers.** The app exchanges data directly between devices over
  Bluetooth, local Wi-Fi, and LAN WebSocket links. There is no backend,
  no cloud, no analytics, no crash reporting, no advertising SDKs.
- **What peers receive.** When you publish an offer or a need, its text,
  a numeric embedding of that text, your public key, and your chosen
  alias are shared with mesh peers in your vicinity — that is the
  entire purpose of the app. Ring negotiation records (lock / fulfil /
  withdraw operations signed by your key) are likewise shared.
  Publish only what you are comfortable showing to people near you.
- **What stays local.** The full exchange history, your reputation
  scores for peers, telemetry readings (battery, thermal, Wi-Fi name),
  and the ML model run entirely on the device. Semantic matching is
  computed on-device; text is never sent to any third party.
- **Permissions.** Location, Bluetooth, and Nearby Wi-Fi permissions
  exist solely because the operating system requires them for local
  radio discovery (and, on iOS, to read the current Wi-Fi name for the
  compute-trust gate). No location coordinates are read, stored, or
  transmitted.
- **Deletion.** Uninstalling the app destroys the local database and
  the key material. Peers retain the operations you previously
  published to them, exactly like a message you already sent.

Contact: rf24krsk@gmail.com

## Русский

**Коротко: ваши данные не покидают устройство, пока вы сами не
опубликуете их ближайшим участникам. Серверов у нас нет, мы ничего не
собираем.**

- **Без аккаунтов.** Ваша личность — пара ключей Ed25519, созданная на
  устройстве и хранимая в защищённом хранилище платформы (Keychain /
  Android Keystore). Мы её не видим.
- **Без серверов.** Приложение обменивается данными напрямую между
  устройствами по Bluetooth, локальному Wi-Fi и WebSocket в локальной
  сети. Нет бэкенда, облака, аналитики, крэш-репортов, рекламных SDK.
- **Что получают участники.** Публикуя предложение или потребность, вы
  делитесь с участниками меша поблизости: текстом, числовым векторным
  представлением текста, своим публичным ключом и выбранным псевдонимом
  — в этом и состоит назначение приложения. Записи переговоров по
  кольцу (операции lock / fulfil / withdraw, подписанные вашим ключом)
  распространяются так же. Публикуйте только то, что готовы показать
  людям рядом.
- **Что остаётся локально.** Полная история обменов, ваши оценки
  надёжности участников, телеметрия (батарея, температура, имя Wi-Fi)
  и ML-модель работают целиком на устройстве. Семантический подбор
  выполняется на устройстве; текст никогда не отправляется третьим
  сторонам.
- **Разрешения.** Доступ к геолокации, Bluetooth и Nearby Wi-Fi нужен
  исключительно потому, что операционная система требует их для
  локального радиообнаружения (а на iOS — для чтения имени текущей
  Wi-Fi-сети в целях доверенного вычислительного шлюза). Координаты
  местоположения не читаются, не хранятся и не передаются.
- **Удаление.** Удаление приложения уничтожает локальную базу данных и
  ключи. У участников остаются операции, которые вы им уже
  опубликовали, — ровно как уже отправленное сообщение.

Контакт: rf24krsk@gmail.com
