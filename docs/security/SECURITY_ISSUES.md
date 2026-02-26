# Security Issue Drafts

These are draft issues to open in your tracker with label `security`.

## 1) Android SDK fingerprint hardcoded in source
- Label: `security`
- Title: `security: remove hardcoded Android SDK fingerprints from Dart source`
- Affected file: `apps/flutter/lib/core/sdk/ren_sdk.dart`
- Risk: fingerprint lifecycle is tied to source commits; operational leakage and brittle rotation.
- Required action:
  1. Migrate to CI-injected values (`--dart-define` or `buildConfigField`).
  2. Block release build if placeholder/default value is used.
- Rotation plan:
  1. Rebuild SDK artifacts.
  2. Generate new SHA-256 fingerprints.
  3. Update CI secrets and backend `SDK_FINGERPRINT_ALLOWLIST`.
  4. Revoke old fingerprints from allowlist.

## 2) Public key authenticity chain incomplete
- Label: `security`
- Title: `security: implement real Ed25519-signed public-key distribution`
- Affected file: `backend/src/route/users.rs`
- Risk: current endpoint emits hash-based placeholder signature, not full authenticity proof.
- Required action:
  1. Store and return genuine Ed25519 signatures.
  2. Verify signatures client-side before using peer public key.
- Rotation plan:
  1. Generate identity keys for active users/devices.
  2. Publish signed public keys with versioning.
  3. Roll clients to strict signature verification.
