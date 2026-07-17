# Google Play Data Safety — заполнение анкеты

Ответы для раздела Play Console → App content → Data safety.
Основание: приложение бессерверное; никакие данные не отправляются
разработчику или третьим лицам. Обмен данными происходит только
device-to-device по инициативе пользователя.

## Overview
| Вопрос | Ответ |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | n/a (данные не собираются) |
| Do you provide a way for users to request that their data is deleted? | n/a (данные не собираются) |

**Обоснование «No».** По определениям Play, "collect" — передача данных
с устройства разработчику или третьим лицам (включая SDK). Aura
OmniMesh не имеет серверов, аналитики и сторонних SDK с сетевой
отправкой; тексты объявлений передаются напрямую другим УСТРОЙСТВАМ
пользователей (peer-to-peer) по явному действию пользователя —
это messaging-подобный обмен, а не сбор данных разработчиком.
Формулировка про P2P-обмен продублирована в описании приложения и в
privacy policy.

## Если ревьюер потребует декларировать P2P-обмен
Консервативный запасной вариант (не активировать без запроса):
- Data types: **Messages → Other in-app messages** (тексты объявлений)
  — collected: No; **shared: No** (передача p2p, не третьим лицам);
  ephemeral: No; required: Yes; purpose: App functionality.

## Пермишены, вызывающие вопросы автоматики
| Пермишен | Зачем | Что писать в Permissions declaration |
|---|---|---|
| ACCESS_FINE_LOCATION | Требование ОС для Bluetooth/Wi-Fi discovery (Nearby Connections) | Location is required by Android for nearby device discovery; the app does not read GPS coordinates |
| BLUETOOTH_SCAN/ADVERTISE/CONNECT (neverForLocation) | Радиообнаружение пиров | Peer discovery for offline mesh exchange |
| NEARBY_WIFI_DEVICES | Wi-Fi discovery на API 33+ | То же |
| POST_NOTIFICATIONS | Уведомления о подтверждении кольца | Local notifications only |

## Прочее
- Ads: **No ads**.
- Target audience: 18+ (обменная площадка).
- Data deletion URL: не требуется (данные не собираются); указать
  privacy policy URL после публикации сайта.
