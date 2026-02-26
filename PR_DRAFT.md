# PR: docs/update-2026-02-26

## Summary of Changes
- Rewritten `README.md` to reflect current code reality and doc index.
- Added `ARCHITECTURE.md` with component/data-flow/sequence diagrams.
- Added `MOBILE_BUILD.md` with iOS `--dart-define` fingerprint flow and Android hardcoded fingerprint analysis + migration plan.
- Added `SECURITY.md` with actual E2EE scope, threat model, key handling, FS limitations.
- Added `API_REFERENCE.md` from actual backend route definitions.
- Added `CONTRIBUTING.md` with PR/test/security/CI guidance.
- Replaced `CHANGELOG.md` with release template and SemVer policy.

## Security Findings Captured in Docs
- Android SDK fingerprints hardcoded in `apps/flutter/lib/core/sdk/ren_sdk.dart`.
- Group/channel messages are not E2EE.
- Public key signature flow currently uses hash placeholder in backend endpoint.

## Review Checklist
- [ ] Documentation matches actual route definitions in `backend/src/route/*`.
- [ ] E2EE claims are limited to private 1:1 only.
- [ ] iOS release command with `REN_IOS_SDK_FINGERPRINT` is present and correct.
- [ ] Android hardcoded fingerprint location and migration plan are documented.
- [ ] No real secrets or fingerprint values were introduced in markdown.
- [ ] Mermaid diagrams render correctly.

## Open Questions
1. Should Android fingerprint migration use only `--dart-define`, or hybrid `buildConfigField + dart-define`?
2. Should public key endpoint be blocked until true Ed25519 signature chain is wired end-to-end?
3. Should group/channel be explicitly labeled non-E2EE in product UX copy in all clients (Flutter + web)?

## Acceptance Checklist
- [ ] Architecture docs correspond to real code paths.
- [ ] Documentation set is structured and internally linked.
- [ ] Build instructions are executable.
- [ ] iOS `--dart-define` fingerprint command documented.
- [ ] Android hardcoded hash location documented.
- [ ] Security model documented with current limitations.
- [ ] No secret leakage in docs.
- [ ] PR includes review checklist and unresolved questions.
