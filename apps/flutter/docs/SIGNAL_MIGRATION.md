# Signal Protocol Migration Guide (Flutter + Native)

This project now routes app-level E2EE operations through a native bridge (`MethodChannel`) and removes the old Rust FFI SDK from Flutter.

## 1. Remove legacy SDK

1. Delete Flutter FFI SDK code:
   - `lib/core/sdk/ren_sdk.dart`
2. Delete Android native binaries:
   - `android/app/src/main/jniLibs/**/libren_sdk.so`
3. Delete iOS static framework:
   - `ios/RenSDK.xcframework`
4. Remove iOS linker force-load flags and framework references:
   - `ios/Podfile`
   - `ios/Runner.xcodeproj/project.pbxproj`
5. Remove macOS dylib copy/reference:
   - `macos/Runner.xcodeproj/project.pbxproj`
6. Remove direct `ffi` dependency from Flutter app `pubspec.yaml`.

## 2. Install Signal native dependencies

## Android (official target)

Use Signal official `libsignal-client` artifact in `android/app/build.gradle.kts` and wire it into the same channel methods listed below.

Current code already sets up secure storage and channels in:
- `android/app/src/main/kotlin/com/example/ren/MainActivity.kt`

## iOS (official target)

Use Signal official iOS/Swift package (`libsignal`) in Xcode/SwiftPM and bind it to the channel methods listed below.

Current code already sets up secure storage and channels in:
- `ios/Runner/AppDelegate.swift`

## 3. MethodChannel contract (single API for Flutter)

Channel: `ren/signal_protocol`

Required methods:
- `initUser({ userId, deviceId })`
  - returns local public bundle payload for server sync
- `encrypt({ peerUserId, deviceId, plaintext, preKeyBundle? }) -> String ciphertext`
- `decrypt({ peerUserId, deviceId, ciphertext }) -> String plaintext`
- `hasSession({ peerUserId, deviceId }) -> bool`
- `getFingerprint({ peerUserId, deviceId }) -> String`

Identity change event channel:
- `ren/signal_protocol/events`
- event payload: `{ type: "identity_changed", peer_user_id, previous_fingerprint, current_fingerprint }`

## 4. Flutter integration

Main client:
- `lib/core/e2ee/signal_protocol_client.dart`

Connected in app DI:
- `lib/main.dart`

Auth initialization:
- `lib/features/auth/data/auth_repository.dart`
- Calls `initUser` after login/register.

Chats integration:
- `lib/features/chats/data/chats_repository.dart`
- Encrypt/decrypt paths call native `encrypt/decrypt` only.
- Payload format for E2EE message body:
  - `{"signal_v":1,"ciphertext_by_user":{"<uid>":"<ciphertext>"}}`
- Native envelope format for direct Signal ciphertext payload:
  - base64(JSON): `{"v":2,"t":"prekey|whisper","b":"<base64(signal_message_bytes)>"}`

## 5. Native secure stores

Android:
- Identity/session metadata in `EncryptedSharedPreferences`
- Identity private key in `Android Keystore`

iOS:
- Identity/session metadata in `Keychain`
- Identity private key in `Keychain`

For strict production parity with Signal design, back these stores with dedicated persistent stores for session state (SQLite/CoreData/Realm) and enforce migration + rotation policies.

## 6. Server responsibilities

Server must remain relay-only:
- store/transmit ciphertext payloads as-is
- expose public key/prekey bundles endpoint for session bootstrap
- never receive plaintext or private keys

Required API (implemented):
- `PATCH /users/signal-bundle` (auth required)
- `GET /users/{id}/public-key` returns public bundle fields
- Bundle now includes Kyber fields for PQ-capable pre-key sessions:
  - `kyber_pre_key_id`
  - `kyber_pre_key`
  - `kyber_pre_key_signature`

## 7. Production hardening checklist

1. Android native layer: finish full migration from transitional crypto to direct `libsignal-client` SessionBuilder/SessionCipher flow.
2. Validate signed prekey / identity signatures before first session.
3. Implement per-device sessions and key rotation.
4. Add identity-change UX flow (block send until user confirms trust).
5. Add replay protection, message counters, and strict ratchet state persistence.
6. Add migration for existing chats and invalidate old non-Signal session states.
7. Add integration tests (Android+iOS) for:
   - fresh bootstrap,
   - session recovery,
   - identity key change alerts,
   - group fanout decrypt.

## 8. Build/test sequence

1. `flutter pub get`
2. `flutter analyze`
3. Android: `flutter build apk --debug`
4. iOS: `cd ios && pod install && cd .. && flutter build ios --debug --simulator`
