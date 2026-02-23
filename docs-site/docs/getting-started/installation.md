---
title: Установка
description: Требования к окружению и установка всех компонентов Ren
sidebar_position: 1
---

# Установка

Это руководство описывает требования к окружению и процесс установки всех компонентов Ren для разработки.

## Требования

### Обязательные

| Компонент | Версия | Примечание |
|-----------|--------|------------|
| **Rust** | 1.75+ | [Установка](https://rustup.rs/) |
| **Flutter** | 3.8+ | [Установка](https://flutter.dev/docs/get-started/install) |
| **PostgreSQL** | 14+ | [Установка](https://www.postgresql.org/download/) |
| **Node.js** | 18+ | Только для frontend |

### Опциональные (для мобильных платформ)

| Компонент | Платформа | Примечание |
|-----------|-----------|------------|
| **Xcode Command Line Tools** | macOS | Для iOS/macOS сборки |
| **Android SDK + NDK** | Android | Для Android сборки |
| **cargo-ndk** | Android | `cargo install cargo-ndk` |
| **cbindgen** | Все | `cargo install cbindgen` |

## Установка компонентов

### 1. Rust

```bash
# Linux/macOS
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Windows
# Скачайте rustup-init.exe с https://rustup.rs/
```

Проверка установки:

```bash
rustc --version
cargo --version
```

### 2. Flutter

#### Linux

```bash
# Скачать Flutter
cd ~
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:$HOME/flutter/bin"

# Добавить в ~/.bashrc или ~/.zshrc
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# Принять лицензии
flutter doctor --android-licenses
```

#### macOS

```bash
brew install --cask flutter
```

#### Windows

```powershell
# Скачать и установить Flutter SDK с https://flutter.dev
# Добавить в PATH: C:\src\flutter
```

Проверка установки:

```bash
flutter doctor
```

### 3. PostgreSQL

#### Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

#### macOS

```bash
brew install postgresql@14
brew services start postgresql@14
```

#### Windows

Скачайте установщик с https://www.postgresql.org/download/windows/

Проверка установки:

```bash
psql --version
```

### 4. Node.js (для frontend)

#### Linux/macOS

```bash
# Через nvm (рекомендуется)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
nvm use 18

# Или через пакетный менеджер
# Ubuntu/Debian
sudo apt install nodejs npm

# macOS
brew install node@18
```

#### Windows

Скачайте установщик с https://nodejs.org/

Проверка установки:

```bash
node --version
npm --version
```

### 5. Android SDK и NDK (для Android сборки)

```bash
# Установите Android Studio
# Затем через SDK Manager установите:
# - Android SDK Platform (API 33+)
# - Android SDK Build-Tools
# - Android NDK (Side by Side)

# Установите cargo-ndk
cargo install cargo-ndk
```

### 6. Дополнительные инструменты

```bash
# cbindgen для генерации C заголовков
cargo install cbindgen

# wasm-pack для WASM сборки (если нужен frontend)
cargo install wasm-pack
```

## Проверка окружения

После установки всех компонентов выполните:

```bash
# Проверка Rust
rustc --version  # Должно быть 1.75+
cargo --version

# Проверка Flutter
flutter doctor

# Проверка PostgreSQL
psql --version  # Должно быть 14+

# Проверка Node.js (если нужен frontend)
node --version  # Должно быть 18+
npm --version
```

## Следующие шаги

- [Быстрый старт](/docs/getting-started/quick-start) — минимальный пример запуска
- [Конфигурация](/docs/getting-started/configuration) — описание всех параметров
