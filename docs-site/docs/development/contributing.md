---
title: Вклад в проект
description: Как настроить dev-окружение и правила оформления PR
sidebar_position: 1
---

# Вклад в проект

Это руководство описывает процесс настройки окружения для разработки и правила оформления pull request.

## Настройка dev-окружения

### 1. Клонирование репозитория

```bash
git clone https://github.com/taiidzy/ren.git
cd ren
```

### 2. Установка зависимостей

Следуйте руководству [Установка](/docs/getting-started/installation).

### 3. Запуск backend

```bash
cd backend

# Создать .env файл
cp .env.example .env
# Отредактируйте .env под ваше окружение

# Запустить
cargo run
```

### 4. Запуск Flutter приложения

```bash
cd apps/flutter

# Собрать Ren-SDK (если нужно)
cd ../Ren-SDK && ./build.sdk.sh && cd ../flutter

# Установить зависимости
flutter pub get

# Запустить
flutter run
```

### 5. Запуск frontend

```bash
cd frontend

# Установить зависимости
npm install

# Создать .env
echo "VITE_API_URL=http://localhost:8081" > .env

# Запустить dev-сервер
npm run dev
```

## Структура проекта

```
ren/
├── Ren-SDK/          # Rust ядро шифрования
├── backend/          # Axum сервер
├── frontend/         # React веб-приложение
├── apps/
│   ├── flutter/      # Flutter мобильное приложение
│   └── ios/          # iOS нативное приложение
├── nginx/            # Nginx конфигурация
├── scripts/          # Скрипты сборки/запуска
└── docs/             # Документация
```

## Ветка разработки

### Основная ветка

- `main` — основная ветка для продакшена
- Все изменения вливаются через pull request

### Ветки для функций

```bash
# Создать ветку для новой функции
git checkout -b feature/<name>

# Ветка для исправления бага
git checkout -b fix/<name>

# Ветка для рефакторинга
git checkout -b refactor/<name>
```

### Соглашения по именованию

| Префикс | Назначение |
|---------|------------|
| `feature/` | Новая функциональность |
| `fix/` | Исправление бага |
| `refactor/` | Рефакторинг без изменений функциональности |
| `docs/` | Изменения документации |
| `test/` | Добавление/изменение тестов |
| `chore/` | Изменения конфигурации, сборки |

## Коммиты

### Формат коммитов

Используйте [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Типы коммитов

| Тип | Описание |
|-----|----------|
| `feat` | Новая функциональность |
| `fix` | Исправление бага |
| `docs` | Изменения документации |
| `style` | Форматирование, пробелы, точки с запятой |
| `refactor` | Рефакторинг кода |
| `test` | Добавление тестов |
| `chore` | Изменения сборки, конфигурации |

### Примеры

```bash
# Новая функция
git commit -m "feat(chats): добавить поддержку голосовых сообщений"

# Исправление
git commit -m "fix(auth): исправить ошибку валидации пароля"

# Рефакторинг
git commit -m "refactor(sdk): упростить логику шифрования"

# Документация
git commit -m "docs: обновить README с инструкциями по установке"
```

## Pull Request

### Создание PR

1. **Fork** репозиторий (если нет прав на запись)
2. Создайте ветку: `git checkout -b feature/my-feature`
3. Внесите изменения
4. Закоммитьте: `git commit -m "feat: добавить функцию"`
5. Отправьте: `git push origin feature/my-feature`
6. Откройте Pull Request на GitHub

### Требования к PR

- [ ] Код следует стилю проекта
- [ ] Добавлены тесты для новой функциональности
- [ ] Все тесты проходят
- [ ] Документация обновлена
- [ ] Описаны изменения в PR description

### Шаблон PR description

```markdown
## Описание
Краткое описание изменений.

## Тип изменений
- [ ] Новая функциональность
- [ ] Исправление бага
- [ ] Рефакторинг
- [ ] Документация
- [ ] Тесты

## Проверка
- [ ] `cargo test` проходит
- [ ] `flutter test` проходит
- [ ] `npm test` проходит

## Скриншоты (если применимо)
<!-- Скриншоты UI изменений -->

## Related Issues
Closes #123
```

## Code Style

### Rust

Следуйте [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/):

```rust
// Используйте rustfmt
cargo fmt

// Используйте clippy для линтинга
cargo clippy -- -D warnings
```

### Dart/Flutter

Следуйте [Effective Dart](https://dart.dev/guides/language/effective-dart):

```bash
# Форматирование
dart format .

# Анализ
flutter analyze
```

### TypeScript/React

Следуйте [TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html):

```bash
# Форматирование
npm run lint

# Типизация
npm run type-check
```

## Тестирование

### Backend тесты

```bash
cd backend

# Запустить все тесты
cargo test

# Запустить конкретный тест
cargo test test_name

# Запустить с выводом
cargo test -- --nocapture
```

### Flutter тесты

```bash
cd apps/flutter

# Запустить все тесты
flutter test

# Запустить с покрытием
flutter test --coverage

# Просмотр покрытия
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Frontend тесты

```bash
cd frontend

# Запустить тесты
npm test

# Запустить в watch режиме
npm run test:watch
```

## Документация

При добавлении новой функциональности:

1. Обновите `intro.md` если изменились ключевые возможности
2. Добавьте страницу в `guides/` для пользовательских сценариев
3. Обновите `api/reference.md` для новых endpoint
4. Обновите `architecture/overview.md` для изменений архитектуры

## Ревью кода

### Чек-лист ревьюера

- [ ] Код решает заявленную проблему
- [ ] Нет избыточной сложности
- [ ] Обработаны краевые случаи
- [ ] Нет утечек ресурсов
- [ ] Соблюдены соглашения об именовании
- [ ] Добавлены тесты
- [ ] Документация обновлена

### Время ответа

- Обычные PR: 2-3 рабочих дня
- Критические исправления: 24 часа

## Release процесс

### Версионирование

Используется [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH
```

- `MAJOR` — ломающие изменения
- `MINOR` — новая функциональность
- `PATCH` — исправления багов

### Создание релиза

1. Обновите `CHANGELOG.md`
2. Создайте тег: `git tag v1.2.3`
3. Отправьте тег: `git push origin v1.2.3`
4. Создайте Release на GitHub

## Контакты

- **Email:** taiidzy@yandex.ru
- **Issues:** https://github.com/taiidzy/ren/issues
