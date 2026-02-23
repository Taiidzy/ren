---
title: Changelog
description: История изменений Ren
sidebar_position: 1
---

# Changelog

Все значимые изменения проекта задокументированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/), проект следует [Semantic Versioning](https://semver.org/).

## [Unreleased] - 2026-02-24

### Добавлено

#### Безопасность (P0)

- **P0-1: Delete Message Authorization**
  - Исправлена уязвимость удаления чужих сообщений любым участником чата
  - Добавлена проверка прав: только автор или admin/owner могут удалять
  - Добавлен аудит удаления через поля `deleted_at` и `deleted_by`
  - Возвращает `403 Forbidden` при попытке удаления чужого сообщения

- **P0-2: Public Key Authentication (MITM Prevention)**
  - Добавлена криптографическая верификация публичных ключей
  - Внедрены Ed25519 identity keys для подписи X25519 публичных ключей
  - API `/users/:id/public-key` возвращает `{ public_key, signature, key_version, identity_key, signed_at }`
  - Добавлена миграция БД с колонками `identity_pubk`, `key_version`, `key_signed_at`

- **P0-3: Recovery Scheme Hardening**
  - Заменён 6-символьный recovery key на 12-словные мнемонические фразы BIP39 (~128 бит энтропии)
  - Внедрён Argon2id memory-hard KDF для деривации ключа восстановления (64 MiB, 3 итерации)
  - Добавлены функции `generateRecoveryPhrase()`, `deriveRecoveryKeyArgon2id()`, `generateRecoverySalt()`

- **P0-5: Group/Channel E2EE Warning**
  - Добавлено предупреждение о том, что групповые сообщения не защищены E2EE
  - Создан виджет `GroupE2EEWarning` для отображения в заголовке групповых чатов

#### High Priority (P1)

- **P1-6: Anti-Replay/Idempotency**
  - Добавлено поле `client_message_id` (UUID) в таблицу `messages`
  - Создан уникальный индекс `(chat_id, sender_id, client_message_id)`
  - Реализована проверка идемпотентности — возврат существующего сообщения при дубликате

- **P1-7: Rate Limiting**
  - Внедрён middleware `RateLimiter` с IP + account bucketing
  - Создан `AuthRateLimiter` для auth-эндпоинтов с exponential backoff
  - Конфигурация: 5 попыток входа, lockout от 1 минуты до 1 часа

- **P1-9: SDK Integrity Check**
  - Усилена проверка целостности SDK
  - Явная проверка SHA256 hash SDK библиотеки на Android при инициализации

#### Функционал

- **Никнеймы пользователей**
  - Добавлено поле `nickname` (отображаемое имя) для пользователей
  - Поддержка в регистрации, профиле, чатах
  - Миграция БД: колонка `users.nickname`

- **Управление чатами**
  - Создание групп и каналов с ролевой моделью (member/admin/owner)
  - Добавление/удаление участников
  - Изменение роли участника
  - Загрузка/удаление аватара чата

- **Доставка и прочтение сообщений**
  - Добавлено поле `is_delivered` в `messages`
  - Endpoint `POST /chats/:id/delivered`
  - WebSocket события `message_delivered`, `message_read`
  - Визуальные индикаторы (галочки) в UI

- **Метаданные последнего сообщения в списке чатов**
  - Расширен `GET /chats` с информацией о последнем сообщении
  - Корректный `unread_count` для списка чатов

### Изменено

#### Backend

- **Групповые/каналные сообщения**
  - Реализована базовая серверная модель групп и каналов в режиме non-E2EE
  - Realtime-события: `member_added`, `member_removed`, `member_role_changed`, `chat_created`

- **Владелец чата**
  - Исправлено поведение `DELETE /chats/:id` для owner
  - Owner не может выйти из чата (должен удалить чат или передать права)

#### Flutter

- **Рефакторинг архитектуры чатов**
  - Вынесены presentation controllers: `ChatPageRealtimeCoordinator`, `ChatsRealtimeCoordinator`, `ChatPendingAttachmentsController`
  - Декомпозированы UI компоненты: `chat_members_sheet_body`, `chat_group_channel_sheets`, `chat_message_context_menu`

- **Уведомления**
  - Исправлено внутреннее уведомление когда собеседник находится в чате с отправителем
  - Добавлено отслеживание текущего открытого чата

- **UX создания групп/каналов**
  - Новый UI/UX через поиск с bottom sheet
  - Поиск пользователей с отображением аватарки и имени

- **Отображение отправителя в групповых чатах**
  - Добавлены `senderName` и `senderAvatarUrl` в модель `ChatMessage`
  - Отображение информации об отправителе над bubble сообщения

### Исправлено

#### Backend

- Исправлены предупреждения компиляции Rust
- Обновлён API `base64::encode` → `base64::engine::general_purpose::STANDARD.encode()`
- Исправлены unused variable warnings

#### Flutter

- Исправлен баг с состоянием профиля после logout/login
- Исправлены FFI type compatibility issues
- Обновлены стили полей ввода в профиле

### Удалено

- Убрана отдельная кнопка `Отмена` в bottom sheet вложений

---

## [0.2.0] - 2026-02-22

### Добавлено

- Поддержка никнеймов пользователей
- Групповые и каналные чаты
- Ролевая модель (member/admin/owner)
- Доставка и прочтение сообщений
- Аватары чатов

### Изменено

- Обновлена схема БД с поддержкой групп/каналов
- Улучшена производительность списка чатов

---

## [0.1.0] - 2026-02-13

### Добавлено

- E2EE шифрование для приватных чатов
- Регистрация и аутентификация пользователей
- WebSocket для real-time событий
- Загрузка файлов (до 50MB)
- Typing indicators
- Presence система

---

## [Unreleased] - 2025-12-23

### Добавлено

- Начальная версия проекта
- Базовая архитектура
- Ren-SDK с криптографией
- Backend на Axum
- Flutter приложение
