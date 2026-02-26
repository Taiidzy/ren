# Ren

Self-hosted messenger monorepo with Flutter client, Rust backend, and Rust crypto SDK.

## Current Scope (as of 2026-02-26)
- Primary production path: `apps/flutter` + `backend` + `Ren-SDK`.
- `frontend` and `apps/ios` exist, but are not the primary mobile production path.
- E2EE is implemented for **private 1:1 chats**.
- Group/channel chats are **not E2EE** (server can access plaintext payloads there).

## Repository Layout
- `apps/flutter` - Flutter mobile app (iOS/Android).
- `backend` - Axum + PostgreSQL API and WebSocket server.
- `Ren-SDK` - Rust cryptography core (FFI + WASM).
- `frontend` - React web app (separate client path).
- `docs` - security plans and technical docs.

## Documentation Index
- [Architecture](ARCHITECTURE.md)
- [Mobile Build](MOBILE_BUILD.md)
- [Security & E2EE](SECURITY.md)
- [API Reference](API_REFERENCE.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Quick Start

### 1. Backend
```bash
cd backend
cp .env.example .env 2>/dev/null || true
cargo run
```

Required environment variables (see details in [MOBILE_BUILD.md](MOBILE_BUILD.md)):
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`
- `JWT_SECRET`

Optional security variable:
- `ENABLE_EXTERNAL_GEO` (`1` to enable external geo lookup; default disabled)

### 2. Flutter app
```bash
cd apps/flutter
flutter pub get
flutter run
```

For iOS release, use the documented command in [MOBILE_BUILD.md](MOBILE_BUILD.md).

## Security Notes
- Do not commit secrets (`JWT_SECRET`, API keys, private keys, CI tokens).
- Do not commit secrets into markdown/docs.
