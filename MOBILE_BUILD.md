# Mobile Build

## Build Matrix
- Flutter app path: `apps/flutter`.
- iOS uses `apps/flutter/ios/RenSDK.xcframework`.
- Android uses `apps/flutter/android/app/src/main/jniLibs/*/libren_sdk.so`.

## Environment Variables
- Backend:
  - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`
  - `JWT_SECRET`
- Flutter runtime defines:
  - `REN_ANDROID_FLAG_SECURE`
  - `REN_IOS_PRIVACY_OVERLAY`
  - `REN_IOS_ANTI_CAPTURE`

## iOS Build

### Mandatory release run command
```bash
flutter run --release
```

## Android Build

### Current state
- Android SDK binaries are synced from `Ren-SDK` build outputs into:
  - `apps/flutter/android/app/src/main/jniLibs/*/libren_sdk.so`

## Debug vs Release
- Debug:
  - Faster iteration, security hardening may differ.
- Release:
  - Required to validate production-like runtime behavior and performance.

## Signing
- Android `build.gradle.kts` currently uses debug signing for `release` placeholder setup.
- Replace with production keystore configuration in CI.
- iOS signing must use proper provisioning profile/certificates for release deployment.

## CI Recommendations
- Add jobs:
  - build backend
  - `flutter analyze` + `flutter test`
  - release build smoke for Android/iOS
- Add security checks:
  - secret scanning (`gitleaks`)
  - basic SAST (`semgrep`)

## Example CI Checks
```bash
# markdown lint
npx markdownlint-cli2 "**/*.md"

# secret scan
gitleaks detect --source .

# flutter static checks
cd apps/flutter && flutter analyze && flutter test
```
