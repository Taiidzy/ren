# Changelog

## [Unreleased] - 2026-02-22

### Flutter App (`apps/flutter`)

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
  - диалог для изменения названия чата;
  - заглушка для смены аватарки (требует backend интеграции);
  - добавлен метод `updateChatInfo` в API и репозиторий.
- Файлы:
  - `lib/features/chats/data/chats_api.dart` — endpoint `/chats/:id`;
  - `lib/features/chats/data/chats_repository.dart` — метод `updateChatInfo`;
  - `lib/features/chats/presentation/chat_page.dart` — `_editChatInfo`, `_changeAvatar`.

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

#### Chat info update endpoint
- Добавлен endpoint `PATCH /chats/:id` для обновления информации о чате:
  - поддержка обновления `title` и `avatar`;
  - проверка прав доступа (только владелец);
  - валидация входных данных.
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
