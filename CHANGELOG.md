# Changelog

## 2026-03-01

### Added
- Native Signal Protocol bridge for Flutter via `MethodChannel` / `EventChannel` with unified API:
  - `initUser`
  - `encrypt`
  - `decrypt`
  - `hasSession`
  - `getFingerprint`
- Identity change notifications from native layers to Flutter (`identity_changed` event).
- Backend Signal bundle support for Kyber fields:
  - `kyber_pre_key_id`
  - `kyber_pre_key`
  - `kyber_pre_key_signature`
- Migration documentation:
  - `apps/flutter/docs/SIGNAL_MIGRATION.md`

### Changed
- Flutter app switched from legacy SDK to Signal native client integration:
  - Added `SignalProtocolClient` bridge in Flutter.
  - Auth bootstrap now initializes native Signal user and uploads bundle.
  - Chats encrypt/decrypt paths now call native Signal channel.
- iOS native implementation rewritten to official `LibSignalClient` protocol flow:
  - persistent Keychain-backed stores for identity/pre-keys/sessions
  - pre-key processing and Signal message decrypt/encrypt through native API
- Android native implementation moved toward official `libsignal-client` session flow:
  - Signal session bootstrap/encryption/decryption pipeline in native layer
  - secure state persistence in `EncryptedSharedPreferences` (with `MasterKey`)
- iOS build configuration updated for `LibSignalClient` integration and module compatibility.
- Local plugin override added for `ffmpeg_kit_min_gpl` to fix simulator linking:
  - use CocoaPods binary with simulator-compatible XCFramework slices

### Removed
- Legacy SDK artifacts and bindings:
  - old Flutter SDK wrapper (`ren_sdk.dart`)
  - Android `libren_sdk.so` binaries
  - iOS `RenSDK.xcframework` references and binaries

### Fixed
- iOS simulator build unblocked:
  - resolved `SignalFfi` module dependency build blocker
  - resolved FFmpeg device-only framework linker failure on simulator
