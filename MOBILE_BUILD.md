# Mobile Build

## Build Matrix
- Flutter app path: `apps/flutter`.
- iOS uses `apps/flutter/ios/RenSDK.xcframework`.
- Android uses `apps/flutter/android/app/src/main/jniLibs/*/libren_sdk.so`.

## Environment Variables
- Backend:
  - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`
  - `JWT_SECRET`
  - `SDK_FINGERPRINT_ALLOWLIST` (optional, comma-separated SHA256 values)
- Flutter runtime defines:
  - `REN_IOS_SDK_FINGERPRINT`
  - `REN_ANDROID_FLAG_SECURE`
  - `REN_IOS_PRIVACY_OVERLAY`
  - `REN_IOS_ANTI_CAPTURE`

## iOS Build

### Mandatory release run command
```bash
flutter run --release --dart-define="REN_IOS_SDK_FINGERPRINT=<IOS_SDK_SHA256>"
```

### What `REN_IOS_SDK_FINGERPRINT` is
- SHA-256 fingerprint of the built iOS SDK static library.
- Client sends it as `X-SDK-Fingerprint`.
- Backend validates it against `SDK_FINGERPRINT_ALLOWLIST` when allowlist is enabled.

### Where fingerprint comes from
1. Build/sync SDK artifacts (`Ren-SDK/build.sdk.sh` or `scripts/run-ios-release-with-sdk.sh`).
2. Compute SHA-256 for:
   - `apps/flutter/ios/RenSDK.xcframework/ios-arm64/libren_sdk.a`
3. Example (local only, do not commit output):
```bash
shasum -a 256 apps/flutter/ios/RenSDK.xcframework/ios-arm64/libren_sdk.a | awk '{print tolower($1)}'
```

### Secure storage of this value
- Store in CI secret manager (GitHub Actions secrets, GitLab CI variables, Vault, etc.).
- Pass as `--dart-define` at build/run time.
- Never commit the actual hash in markdown, source code, or shell history artifacts checked into git.

## Android Build

### Current state (hardcoded)
SDK fingerprints are hardcoded in:
- `apps/flutter/lib/core/sdk/ren_sdk.dart:19` (map `_androidPinnedSdkSha256`)

This is the exact location where hash values are embedded in source.

### Safe alternatives
1. `--dart-define`
   - Read per-ABI fingerprint from `String.fromEnvironment` values.
2. Gradle `buildConfigField`
   - Inject from CI env and pass via platform channel to Dart.
3. CI secrets
   - Store fingerprints in secret variables, inject at build time.
4. Secret Manager
   - Pull fingerprints in CI from Vault/Secret Manager, never commit.

### Migration plan (Android)
1. Remove literal hashes from `_androidPinnedSdkSha256`.
2. Add required `String.fromEnvironment` keys per ABI (or single allowlist string).
3. Inject values in CI build command:
   - `flutter build apk --release --dart-define=REN_ANDROID_SDK_SHA256_ARM64=<...>`
4. Keep backend `SDK_FINGERPRINT_ALLOWLIST` synchronized with produced SDK artifacts.
5. Add CI gate that fails if placeholder/default fingerprint is used in release.

## Debug vs Release
- Debug:
  - Faster iteration, security hardening may differ.
- Release:
  - Required for integrity/fingerprint attestation behavior to reflect production usage.

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
  - deny hardcoded fingerprint literals in Dart sources for release branches

## Example CI Checks
```bash
# markdown lint
npx markdownlint-cli2 "**/*.md"

# secret scan
gitleaks detect --source .

# flutter static checks
cd apps/flutter && flutter analyze && flutter test
```
