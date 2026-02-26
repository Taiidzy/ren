# Security Issue Drafts

These are draft issues to open in your tracker with label `security`.

## 1) Public key authenticity chain incomplete
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
