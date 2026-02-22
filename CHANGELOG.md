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
