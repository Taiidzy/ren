# Changelog

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
  - заменён `PopupMenuButton` на кастомный `_MemberActionDropdown`;
  - единый стиль glass surface на протяжении всего UI.
- Файлы:
  - `lib/features/chats/presentation/chat_page.dart` — `_ChatMembersSheetBody` обновлён.

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
