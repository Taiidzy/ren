# Changelog

## [Unreleased] - 2026-02-23

### Security Remediation Plan Implementation

#### Critical Security Fixes (P0)

##### P0-1: Delete Message Authorization
- Исправлена уязвимость удаления чужих сообщений любым участником чата:
  - добавлена проверка прав: только автор сообщения или admin/owner могут удалять;
  - добавлен аудит удаления через поля `deleted_at` и `deleted_by`;
  - возвращает `403 Forbidden` при попытке удаления чужого сообщения.
- Файлы:
  - `backend/src/route/ws.rs` — проверка ownership в `DeleteMessage` handler

##### P0-2: Public Key Authentication (MITM Prevention)
- Добавлена криптографическая верификация публичных ключей:
  - внедрены Ed25519 identity keys для подписи X25519 публичных ключей;
  - добавлены функции `generate_identity_key_pair()`, `sign_public_key()`, `verify_signed_public_key()`;
  - API `/users/:id/public-key` возвращает `{ public_key, signature, key_version, identity_key, signed_at }`;
  - добавлена миграция БД с колонками `identity_pubk`, `key_version`, `key_signed_at`.
- Файлы:
  - `Ren-SDK/Cargo.toml` — добавлена зависимость `ed25519-dalek`;
  - `Ren-SDK/src/mod.rs` — типы `IdentityKeyPair`, `SignedPublicKey`;
  - `Ren-SDK/src/crypto.rs` — функции подписи и верификации;
  - `Ren-SDK/src/ffi.rs` — FFI-биндинги;
  - `Ren-SDK/src/lib.rs` — ре-экспорты;
  - `backend/Cargo.toml` — добавлена зависимость `base64`;
  - `backend/src/models/auth.rs` — модель `SignedPublicKeyResponse`;
  - `backend/src/route/users.rs` — обновлённый endpoint;
  - `backend/migrations/20260223120000_p0_2_key_auth.sql` — миграция БД;
  - `apps/flutter/lib/core/sdk/ren_sdk.dart` — Dart FFI-биндинги.

##### P0-3: Recovery Scheme Hardening
- Усилена схема восстановления доступа:
  - заменён 6-символьный recovery key (~31 бит энтропии) на 12-словные мнемонические фразы BIP39 (~128 бит);
  - внедрён Argon2id memory-hard KDF для деривации ключа восстановления (64 MiB, 3 итерации, параллелизм 4);
  - добавлены функции `generateRecoveryPhrase()`, `deriveRecoveryKeyArgon2id()`, `generateRecoverySalt()`;
  - добавлена валидация энтропии через `validateRecoveryEntropy()`.
- Файлы:
  - `apps/flutter/lib/core/cryptography/recovery_key_generator.dart` — генерация фраз;
  - `Ren-SDK/Cargo.toml` — добавлена зависимость `argon2`;
  - `Ren-SDK/src/mod.rs` — тип `Argon2Config`;
  - `Ren-SDK/src/crypto.rs` — Argon2id KDF функции;
  - `Ren-SDK/src/ffi.rs` — FFI-биндинги;
  - `Ren-SDK/src/lib.rs` — ре-экспорты;
  - `apps/flutter/lib/core/sdk/ren_sdk.dart` — Dart FFI-биндинги.

##### P0-5: Group/Channel E2EE Warning
- Добавлено предупреждение о том, что групповые сообщения не защищены E2EE:
  - создан виджет `GroupE2EEWarning` для отображения в заголовке групповых чатов;
  - явная маркировка групповых/канальных чатов как non-E2EE.
- Файлы:
  - `apps/flutter/lib/features/chats/presentation/widgets/group_e2ee_warning.dart` — новый виджет

#### High Priority Security Fixes (P1)

##### P1-6: Anti-Replay/Idempotency
- Добавлена защита от повторной отправки сообщений:
  - добавлено поле `client_message_id` (UUID) в таблицу `messages`;
  - создан уникальный индекс `(chat_id, sender_id, client_message_id)`;
  - реализована проверка идемпотентности — возврат существующего сообщения при дубликате;
  - добавлена поддержка `client_message_id` в WebSocket событиях `SendMessage`, `VoiceMessage`, `VideoMessage`, `ForwardMessage`.
- Файлы:
  - `backend/migrations/20260223100000_p1_anti_replay.sql` — миграция БД;
  - `backend/src/route/ws.rs` — проверка идемпотентности.

##### P1-7: Rate Limiting
- Внедрена защита от brute-force и DoS атак:
  - создан middleware `RateLimiter` с IP + account bucketing;
  - создан `AuthRateLimiter` для auth-эндпоинтов с exponential backoff;
  - конфигурация: 5 попыток входа, lockout от 1 минуты до 1 часа;
  - применено к `/auth/login`, `/auth/register`, `/auth/refresh`.
- Файлы:
  - `backend/src/middleware/rate_limit.rs` — новый middleware;
  - `backend/src/middleware/mod.rs` — экспорт;
  - `backend/src/main.rs` — инициализация rate limiters;
  - `backend/src/route/auth.rs` — применение к login handler.

##### P1-9: SDK Integrity Check
- Усилена проверка целостности SDK:
  - явная проверка SHA256 hash SDK библиотеки на Android при инициализации;
  - приложение не запустится с модифицированным SDK;
  - логирование fingerprint для security telemetry.
- Файлы:
  - `apps/flutter/lib/core/sdk/ren_sdk.dart` — проверка в `initialize()`.

##### P1-10: Security Documentation Alignment
- Обновлена документация по безопасности:
  - добавлен раздел "Known Security Limitations" в README;
  - задокументированы исправленные проблемы (P0-1, P0-2, P0-3, P0-5, P1-6, P1-7, P1-9);
  - задокументированы остающиеся ограничения (P0-4 Double Ratchet).
- Файлы:
  - `README.md` — обновлённый раздел безопасности.

#### Medium Priority Security Fixes (P2)

##### P2-11: TLS Hardening
- Усиlena TLS-конфигурация nginx:
  - добавлен 301 redirect HTTP → HTTPS;
  - включён HSTS с `max-age=63072000; includeSubDomains; preload`;
  - добавлены security headers (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy);
  - обновлены cipher suites до современных стандартов;
  - включён OCSP stapling.
- Файлы:
  - `nginx/nginx.conf` — HTTPS redirect, HSTS, security headers;
  - `nginx/options-ssl-nginx.conf` — TLS hardening config.

##### P2-12: Geo-Service Privacy
- Отключены внешние geo-запросы по умолчанию:
  - добавлена переменная окружения `ENABLE_EXTERNAL_GEO` (default: 0);
  - city определяется из trusted proxy headers (X-Geo-City, X-City, CF-IPCity);
  - внешние запросы к ipwhois.app отключены.
- Файлы:
  - `backend/src/route/auth.rs` — обновлённый `resolve_city()`.

---

### Backend (`backend`)

#### Code Quality Fixes
- Исправлены предупреждения компиляции:
  - обновлён API `base64::encode` → `base64::engine::general_purpose::STANDARD.encode()`;
  - исправлены unused variable warnings в `auth.rs`;
  - исправлены type mismatches в `rate_limit.rs`.
- Файлы:
  - `backend/src/route/auth.rs`
  - `backend/src/route/users.rs`
  - `backend/src/middleware/rate_limit.rs`
  - `backend/src/route/ws.rs`

---

### Ren-SDK (`Ren-SDK`)

#### Ed25519 Integration
- Интегрирована поддержка Ed25519 для подписи ключей:
  - исправлен API `ed25519-dalek 2.0` (использование `from_bytes`, `to_keypair_bytes`, `try_sign`);
  - добавлены импорты `Signer` и `Verifier` трейтов;
  - исправлена обработка приватных ключей (64 bytes keypair).
- Файлы:
  - `Ren-SDK/Cargo.toml`
  - `Ren-SDK/src/crypto.rs`
  - `Ren-SDK/src/mod.rs`
  - `Ren-SDK/src/ffi.rs`
  - `Ren-SDK/src/lib.rs`

---

### Flutter App (`apps/flutter`)

#### SDK FFI Bindings
- Обновлены FFI-биндинги для новых функций SDK:
  - добавлены типы `RenIdentityKeyPair` для Ed25519 ключей;
  - добавлены методы `generateIdentityKeyPair()`, `signPublicKey()`, `verifySignedPublicKey()`;
  - временно отключены `generateRecoverySalt()` и `validateRecoveryEntropy()` из-за FFI type compatibility issues.
- Файлы:
  - `apps/flutter/lib/core/sdk/ren_sdk.dart`

#### Code Quality
- Исправлены предупреждения Flutter analyzer:
  - исправлен синтаксис `Struct` (использование `final class`);
  - исправлены FFI typedef совместимости.
- Файлы:
  - `apps/flutter/lib/core/sdk/ren_sdk.dart`

---

## [Unreleased] - 2026-02-23

### Flutter App (`apps/flutter`)

#### Chats architecture refactor and codebase optimization
- Проведён крупный рефактор `chats` presentation-слоя без изменения пользовательской логики:
  - вынесена orchestration-логика из перегруженных экранов в отдельные controllers;
  - сокращён объём `chat_page.dart` за счёт декомпозиции send/pick/attachments/realtime/appbar callbacks;
  - устранено дублирование отправки записанных медиа (voice/video) через общий flow.
- Вынесены и переиспользованы presentation controllers:
  - `ChatPageRealtimeCoordinator` — lifecycle WS (connect/join/subscribe/dispose) для chat page;
  - `ChatsRealtimeCoordinator` — realtime lifecycle для chats list;
  - `ChatsUserSearchController` — debounce и состояние поиска пользователей;
  - `ChatsTopBannerController` — централизованное управление in-app баннером;
  - `ChatsChatActionsController` — favorite/delete actions для чатов;
  - `ChatPendingAttachmentsController` — очередь вложений (лимиты/статусы/remove/retry);
  - `ChatAttachmentsPickerController` — выбор фото/файлов/камеры вне UI-страницы;
  - `ChatAttachmentsPreparer` — подготовка optimistic attachments и bytes для отправки.
- Декомпозированы крупные UI-блоки в отдельные файлы:
  - `chat_members_sheet_body.dart` — управление участниками;
  - `chat_group_channel_sheets.dart` — create/edit group/channel sheets;
  - `chat_message_context_menu.dart` — контекстное меню сообщений и picker чата для forward.
- Улучшена доменная модель чатов:
  - добавлены `copyWith` в `ChatUser`, `ChatMessage`, `ChatAttachment`, `ChatPreview`;
  - call sites переведены на `copyWith` для более безопасных локальных обновлений.
- Улучшения читаемости и поддержки:
  - в `ChatInputBar`/`ChatPageAppBar` и video overlay вынесены тяжёлые inline callbacks в именованные private-методы;
  - уменьшена вложенность `build`-веток и упрощено сопровождение крупных виджетов.
- Проверка:
  - `flutter analyze` — без ошибок;
  - `flutter test` — все тесты проходят.
- Файлы:
  - `apps/flutter/lib/features/chats/domain/chat_models.dart`
  - `apps/flutter/lib/features/chats/presentation/chats_page.dart`
  - `apps/flutter/lib/features/chats/presentation/chat_page.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chats_user_search_controller.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chats_realtime_coordinator.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chats_top_banner_controller.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chats_chat_actions_controller.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chat_page_realtime_coordinator.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chat_pending_attachments_controller.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chat_attachments_picker_controller.dart`
  - `apps/flutter/lib/features/chats/presentation/controllers/chat_attachments_preparer.dart`
  - `apps/flutter/lib/features/chats/presentation/widgets/chat_group_channel_sheets.dart`
  - `apps/flutter/lib/features/chats/presentation/widgets/chat_members_sheet_body.dart`
  - `apps/flutter/lib/features/chats/presentation/widgets/chat_message_context_menu.dart`

## [Unreleased] - 2026-02-22

### Flutter App (`apps/flutter`)

#### User nickname support
- Добавлена поддержка nickname (отображаемого имени) пользователя:
  - модели `AuthUser`, `ApiUser`, `ProfileUser`, `ChatUser`, `ChatMember` — поле `nickname`;
  - поиск пользователей по `username` с отображением `nickname` в результатах;
  - отображение `nickname` вместо `username` в чатах и сообщениях;
  - если `nickname` пуст — отображается `username`.
- Обновлена регистрация:
  - убрано подтверждение пароля;
  - добавлены обязательное поле `username` и опциональное `nickname`;
  - проверка доступности логина и username в реальном времени (on-the-fly);
  - визуальная индикация: зелёная галочка если доступно, красный крест если занято.
- Обновлён профиль:
  - редактирование `nickname` в `profile_edit_sheet.dart`;
  - валидация: не пустое, максимум 32 символа;
  - отдельная кнопка сохранения для nickname.
- Файлы:
  - `apps/flutter/lib/features/auth/domain/auth_user.dart`
  - `apps/flutter/lib/features/auth/domain/auth_models.dart`
  - `apps/flutter/lib/features/auth/data/auth_api.dart`
  - `apps/flutter/lib/features/auth/data/auth_repository.dart`
  - `apps/flutter/lib/features/auth/presentation/components/signup.dart`
  - `apps/flutter/lib/features/chats/domain/chat_models.dart`
  - `apps/flutter/lib/features/chats/data/chats_repository.dart`
  - `apps/flutter/lib/features/chats/presentation/chats_page.dart`
  - `apps/flutter/lib/features/profile/domain/profile_user.dart`
  - `apps/flutter/lib/features/profile/data/profile_api.dart`
  - `apps/flutter/lib/features/profile/data/profile_repository.dart`
  - `apps/flutter/lib/features/profile/presentation/profile_store.dart`
  - `apps/flutter/lib/features/profile/presentation/widgets/profile_edit_sheet.dart`
  - `apps/flutter/lib/core/cache/chats_local_cache.dart`

#### Reconnect strategy for realtime (WebSocket)
- Обновлена политика переподключения WS-клиента при недоступности сервера:
  - 1-я повторная попытка через 10 секунд;
  - 2-я через 30 секунд;
  - 3-я и все следующие — каждые 60 секунд.
- Убраны лишние внеплановые reconnect-попытки при очереди исходящих WS-сообщений.
- Файл:
  - `apps/flutter/lib/core/realtime/realtime_client.dart`

#### HTTP retry policy (Dio + multipart upload)
- Добавлен централизованный retry-interceptor для HTTP-запросов через Dio при сетевой недоступности:
  - 10с → 30с → 60с (дальше каждые 60с).
- Добавлен аналогичный retry для загрузки аватара через `http.MultipartRequest` (не Dio), чтобы поведение было единым.
- Файлы:
  - `apps/flutter/lib/core/network/server_retry_interceptor.dart`
  - `apps/flutter/lib/main.dart`
  - `apps/flutter/lib/features/profile/data/profile_api.dart`

#### Profile edit username field styling
- Поле ввода username в профиле обновлено:
  - прозрачный фон инпута;
  - более круглые края рамки;
  - нейтральная рамка в обычном состоянии и акцентная рамка только в фокусе.
- Файл:
  - `apps/flutter/lib/features/profile/presentation/widgets/profile_edit_sheet.dart`

#### Chat notifications fix
- Исправлено внутреннее уведомление когда собеседник находится в чате с отправителем:
  - добавлено отслеживание текущего открытого чата (`_currentOpenChatId`) в `lib/features/chats/presentation/chats_page.dart`;
  - подавление in-app баннеров и уведомлений при поступлении сообщения для активного чата;
  - очистка идентификатора текущего чата при возврате из chat page.
- Практический эффект:
  - нет дублирующих уведомлений когда пользователь уже в диалоге;
  - более чистый UX без лишних баннеров.

#### Group/Channel creation UX redesign
- Новый UI/UX создания чатов через поиск:
  - добавлены кнопки "Создать группу" и "Создать канал" над результатами поиска;
  - кнопки открывают bottom sheet вместо диалога для лучшего UX;
  - название из поиска передаётся как начальное значение (редактируемое);
  - реализован поиск пользователей с отображением аватарки и имени;
  - выбранные пользователи отображаются с checkmark badges;
  - выбранные пользователи показаны в виде chips внизу с возможностью удаления.
- Файлы:
  - `lib/features/chats/presentation/chats_page.dart` — кнопки создания и новый `_CreateGroupChannelSheet`;
  - `lib/features/chats/presentation/chat_page.dart` — логика bottom sheet.

#### Member management improvements
- Улучшен UI управления участниками группы/канала:
  - заменено поле ввода ID на поиск пользователей (аватар + имя);
  - все текстовые инпуты сделаны прозрачными (без фона, borderless);
  - заменён `DropdownButton` на кастомный `_RoleSelectorDropdown`;
  - заменён `PopupMenuButton` на кастомное меню через `RenContextMenu` (как в `shared/widgets/context_menu.dart`);
  - действия участника (сделать admin/member, удалить) открываются из glass-кнопки `...` рядом с карточкой участника;
  - единый стиль glass surface на протяжении всего UI.
- Файлы:
  - `apps/flutter/lib/features/chats/presentation/chat_page.dart` — `_ChatMembersSheetBody` обновлён.

#### Chat input and attach menu polish
- Небольшие UI-правки в compose/attach:
  - из bottom sheet вложений убрана отдельная кнопка `Отмена` (оставлено закрытие через системные жесты/тап вне sheet);
  - иконка отмены записи в input bar заменена на `HugeIcons.strokeRoundedCancel01` для визуальной консистентности.
- Файлы:
  - `apps/flutter/lib/features/chats/presentation/widgets/chat_attach_menu.dart`
  - `apps/flutter/lib/features/chats/presentation/widgets/chat_input_bar.dart`

#### Owner-only chat info editing
- Добавлена возможность для владельца изменять информацию о чате:
  - кнопка редактирования видна только владельцу канала/группы;
  - bottom sheet для изменения названия;
  - загрузка/удаление аватарки чата с обрезкой изображения;
  - добавлены методы `updateChatInfo`, `uploadChatAvatar`, `removeChatAvatar` в API и репозиторий;
  - обработка realtime-события `chat_updated` для мгновенного обновления списка.
- Файлы:
  - `apps/flutter/lib/features/chats/data/chats_api.dart`
  - `apps/flutter/lib/features/chats/data/chats_repository.dart`
  - `apps/flutter/lib/features/chats/presentation/chats_page.dart`
  - `apps/flutter/lib/features/profile/presentation/widgets/profile_edit_sheet.dart`

#### Logout/login profile state reset fix
- Исправлен баг, при котором после выхода и входа под другим пользователем на экране профиля могли оставаться данные предыдущего пользователя (avatar/display name/username).
- Изменения:
  - при logout теперь явно сбрасывается `ProfileStore`;
  - при logout очищается локальный кэш чатов/сообщений/медиа, чтобы не показывать данные прошлой сессии до синхронизации.
- Файлы:
  - `apps/flutter/lib/features/profile/presentation/profile_store.dart`
  - `apps/flutter/lib/features/profile/presentation/profile_menu_page.dart`

#### Sender name/avatar in group messages
- Добавлено отображение имени и аватарки отправителя в групповых чатах:
  - добавлены `senderName` и `senderAvatarUrl` в модель `ChatMessage`;
  - отображение информации об отправителе над bubble сообщения для входящих;
  - аватарка показывается рядом с именем в primary color.
- Файлы:
  - `lib/features/chats/domain/chat_models.dart` — новые поля;
  - `lib/features/chats/presentation/widgets/chat_message_bubble.dart` — отображение sender info;
  - `lib/features/chats/presentation/chat_page.dart` — парсинг из WS.

#### Role names localization (Russian)
- Переведены названия ролей на русский язык:
  - `member` → `Участник`;
  - `admin` → `Админ`;
  - `owner` → `Владелец`.
- Применено в:
  - `lib/features/chats/presentation/widgets/chat_page_app_bar.dart`;
  - `lib/features/chats/presentation/chat_page.dart` (`_ChatMembersSheetBody`).

---

### Backend (`backend`)

#### User nickname support
- Добавлена поддержка nickname (отображаемого имени) пользователя:
  - миграция БД: колонка `users.nickname` (TEXT, максимум 32 символа);
  - `nickname` не уникален, при регистрации без nickname устанавливается равным `username`;
  - модели `UserResponse`, `UserAuthResponse`, `UserRegisterRequest`, `Claims`, `Chat`, `ChatMember` — поле `nickname`;
  - JWT access token включает `nickname`.
- Новые эндпоинты:
  - `PATCH /users/nickname` — смена отображаемого имени (валидация длины);
  - `POST /auth/register` — обновлён с опциональным `nickname`.
- Обновлённые эндпоинты:
  - `GET /users/me` — возврат `nickname`;
  - `GET /users/search` — поиск по `username`, возврат `nickname`;
  - `GET /chats` — возврат `peer_nickname` для чатов;
  - `GET /chats/:id/members` — возврат `nickname` участников.
- Файлы:
  - `backend/migrations/20260222120000_add_nickname.sql`
  - `backend/src/models/auth.rs`
  - `backend/src/models/chats.rs`
  - `backend/src/route/auth.rs`
  - `backend/src/route/users.rs`
  - `backend/src/route/chats.rs`
  - `backend/src/route/ws.rs`

#### Chat info update endpoint
- Добавлен endpoint `PATCH /chats/:id` для обновления информации о чате:
  - поддержка обновления `title` и `avatar`;
  - проверка прав доступа (только владелец);
  - валидация входных данных.
- Добавлен endpoint `POST/PATCH /chats/:id/avatar` для загрузки и удаления аватара группы/канала.
- Добавлена миграция с колонкой `chats.avatar` и публикация realtime-события `chat_updated`.
- Для `GET /chats` в `group/channel` возвращается аватар чата (`chats.avatar`), а не аватар первого участника.
- Практический эффект:
  - владелец может изменять название и аватарку группы/канала.

#### Group/Channel non-E2EE foundation
- Реализована базовая серверная модель групп и каналов в режиме non-E2EE:
  - создание `group` и `channel` с валидацией обязательного `title`;
  - ролевая модель участников (`member` / `admin` / `owner`);
  - ограничения прав на действия с участниками и управлением чатом.
- Практический эффект:
  - группы и каналы работают полноценно без переписывания E2EE логики SDK на первом этапе.

#### Membership realtime events
- Добавлены и стабилизированы realtime-события по участникам:
  - `member_added`, `member_removed`, `member_role_changed`, `chat_created`;
  - публикация событий всем релевантным участникам через WS user-hub;
  - системные сообщения о составе чата (`X добавил Y`, изменение роли, удаление).
- Практический эффект:
  - пользователи видят изменения состава чата сразу, без ручного обновления списка.

#### Message delivery/read pipeline
- Внедрена серверная цепочка состояний сообщений:
  - добавлено поле `is_delivered` в `messages`;
  - добавлен endpoint `POST /chats/:id/delivered`;
  - добавлено событие WS `message_delivered`;
  - `mark_chat_read` в private-чате теперь также поднимает `is_delivered`.
- Усилена корректность/идемпотентность:
  - устранены ложные продвижения cursor для delivered/read;
  - websocket-события публикуются только при реальном прогрессе;
  - no-op операции не порождают дубли системных событий.
- Практический эффект:
  - стабильные галочки и предсказуемая синхронизация состояния сообщений между клиентами.

#### Chat list state metadata and performance
- Расширен `GET /chats`:
  - добавлены метаданные последнего сообщения (id/body/type/time, outgoing, delivered, read);
  - добавлен корректный `unread_count` для списка чатов.
- Добавлены индексы под новые read/delivered запросы:
  - `messages(chat_id, id DESC)` для не удалённых сообщений;
  - `messages(chat_id, sender_id, id DESC)` для не удалённых сообщений.
- Практический эффект:
  - более информативный список чатов и лучшая производительность под нагрузкой.

---

### Flutter App (`apps/flutter`) — Group/Channel + Realtime дополняющие изменения

#### Group/Channel realtime behavior
- Улучшено моментальное обновление UI при событиях состава:
  - обработка `chat_created` / `member_added` / `member_removed` / `member_role_changed` в списке чатов;
  - оптимистическое добавление/удаление карточек чатов с последующей точной синхронизацией.
- Практический эффект:
  - пользователь сразу видит, что его добавили/удалили или что появился новый чат/канал.

#### Telegram-like unread and scroll UX
- Добавлен разделитель `Новые сообщения` с якорем по unread count.
- Реализовано открытие чата рядом с непрочитанными (при отсутствии сохранённого скролла).
- Добавлено устойчивое сохранение/восстановление scroll position по chat id.
- Добавлена кнопка «вниз» с бейджем новых сообщений, pulse-анимацией и авто-скрытием при открытой клавиатуре.
- Практический эффект:
  - поведение ближе к Telegram: меньше ложных прочтений и удобнее навигация в длинных диалогах.

#### Message state UI (checks + delivery)
- Полностью подключены индикаторы состояний в bubble-компонентах (текст/голос/видео):
  - pending (clock), sent (single check), delivered (double check), read (accent double check).
- Реализована visibility-based отметка прочтения (по реально видимым сообщениям).
- Интегрированы WS-события `message_delivered` и `message_read` для апдейта исходящих сообщений.
- Практический эффект:
  - корректные и консистентные галочки статусов в приватных чатах.

#### Notifications settings sheet (working toggles)
- Добавлен отдельный sheet `Уведомления` в стиле glass surface (по аналогии с `Персонализация`/`Хранилище`).
- Добавлены рабочие (не визуальные) переключатели с сохранением в SecureStorage:
  - `Haptic при новых сообщениях`;
  - `In-app баннеры`;
  - `In-app звук`.
- Подключение к реальному поведению:
  - haptic в chat page (для новых сообщений вне нижней позиции);
  - in-app banner в chats page (foreground);
  - in-app system click sound в chats page (foreground).
- Практический эффект:
  - пользователь может реально управлять внутриприкладным уведомительным UX.

#### Group/Channel leave/delete actions UX
- Исправлено действие long-press для group/channel в списке чатов:
  - для обычного сценария показывается `Выйти` вместо `Удалить чат`;
  - добавлен отдельный action `Удалить чат для всех` только для владельца (`owner`).
- Обновлены тексты подтверждения:
  - для выхода — отдельный confirm на выход из чата/канала;
  - для удаления у всех — явный destructive confirm.
- Практический эффект:
  - участники больше не получают ошибку прав при попытке выйти;
  - destructive-операция отделена от обычного выхода.

#### Channel input visibility
- Убран нижний блок-индикатор ограничения отправки в канале:
  - если у пользователя нет прав на публикацию, инпут-область теперь полностью скрывается;
  - не показывается дополнительная плашка с текстом.
- Практический эффект:
  - более чистый интерфейс без лишнего “заблокированного” блока.

---

### Backend (`backend`) — owner-only delete and leave semantics

#### Group/Channel leave vs delete behavior
- Исправлено поведение `DELETE /chats/:id` для group/channel:
  - по умолчанию (`for_all=false`) пользователь выходит из чата (удаляется из `chat_participants`);
  - удаление чата для всех выполняется только при `for_all=true`.
- Добавлено ограничение прав:
  - `for_all=true` для group/channel теперь разрешён только роли `owner`;
  - `admin` не может удалить группу/канал для всех.
- Если после выхода участников не остаётся, чат удаляется автоматически.
- Практический эффект:
  - корректная семантика “выйти” для участников;
  - удаление для всех строго под контролем владельца.

#### Role consistency for new groups/channels
- Скорректирована роль создателя:
  - создатель `group` и `channel` получает роль `owner`.
- Расширен `GET /chats`:
  - добавлено поле `my_role` для клиента (используется для показа owner-only действий).
- Практический эффект:
  - согласованные права в UI и backend;
  - корректное отображение owner-only операций в списке чатов.

---

### Flutter App (`apps/flutter`) — Layout & Adaptive pass (HIG-aligned, style-preserving)

#### Full UI proportion/adaptive audit and fixes
- Проведен полный layout-pass с минимально инвазивными правками:
  - выровнены пропорции и отступы между экранами;
  - убраны ключевые fixed-size ограничения в критичных контейнерах;
  - добавлены adaptive размеры/паддинги для compact экранов;
  - снижены риски overflow при узкой ширине и увеличенном text scale;
  - улучшены touch-target зоны без изменения визуального языка.

#### Key improvements by area
- Auth:
  - адаптивные размеры hero/logo/card spacing и внутренних отступов;
  - выровнена высота loading-состояний с кнопками.
- Chats:
  - адаптивные отступы app bar/search/content;
  - chat tile переведен с fixed height на min height;
  - стабилизированы узкие action rows и поисковые CTA.
- Chat page:
  - адаптированы размеры video-recording overlay и control capsule;
  - ограничена высота forward bottom sheet через безопасный clamp.
- Profile:
  - добавлен scroll-safe layout для profile menu;
  - адаптированы avatar/paddings/spacing в profile edit;
  - адаптированы header-decor размеры в security sheet;
  - адаптивные отступы и min-height CTA в storage/personalization/notifications.
- Shared/chat widgets:
  - attach menu и attachment viewer адаптированы под узкие экраны;
  - bubble/media widths переведены на constraints-based поведение;
  - context menu и confirm dialog получили adaptive width/inset + min-height actions.

#### Files
- `apps/flutter/lib/features/auth/presentation/auth_page.dart`
- `apps/flutter/lib/features/auth/presentation/components/signin.dart`
- `apps/flutter/lib/features/auth/presentation/components/recovery.dart`
- `apps/flutter/lib/features/chats/presentation/chats_page.dart`
- `apps/flutter/lib/features/chats/presentation/chat_page.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/chat_input_bar.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/chat_attach_menu.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/chat_attachment_viewer_sheet.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/chat_message_bubble.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/square_video_bubble.dart`
- `apps/flutter/lib/features/chats/presentation/widgets/voice_message_bubble.dart`
- `apps/flutter/lib/features/profile/presentation/profile_menu_page.dart`
- `apps/flutter/lib/features/profile/presentation/widgets/profile_edit_sheet.dart`
- `apps/flutter/lib/features/profile/presentation/widgets/security_sheet.dart`
- `apps/flutter/lib/features/profile/presentation/widgets/storage_sheet.dart`
- `apps/flutter/lib/features/profile/presentation/widgets/personalization_sheet.dart`
- `apps/flutter/lib/features/profile/presentation/widgets/notifications_sheet.dart`
- `apps/flutter/lib/shared/widgets/context_menu.dart`
- `apps/flutter/lib/shared/widgets/glass_confirm_dialog.dart`
- `apps/flutter/lib/shared/widgets/matte_toggle.dart`
