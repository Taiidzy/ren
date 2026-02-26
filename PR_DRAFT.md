# PR: docs/update-2026-02-26

## Summary of Changes
- Rewritten `README.md` to reflect current code reality and doc index.
- Added `ARCHITECTURE.md` with component/data-flow/sequence diagrams.
- Added `MOBILE_BUILD.md` with current iOS/Android build flow.
- Added `SECURITY.md` with actual E2EE scope, threat model, key handling, FS limitations.
- Added `API_REFERENCE.md` from actual backend route definitions.
- Added `CONTRIBUTING.md` with PR/test/security/CI guidance.
- Replaced `CHANGELOG.md` with release template and SemVer policy.

## Security Findings Captured in Docs
- Group/channel messages are not E2EE.
- Public key signature flow currently uses hash placeholder in backend endpoint.

## Review Checklist
- [ ] Documentation matches actual route definitions in `backend/src/route/*`.
- [ ] E2EE claims are limited to private 1:1 only.
- [ ] Build instructions are executable and up to date.
- [ ] No real secrets were introduced in markdown.
- [ ] Mermaid diagrams render correctly.

## Open Questions
1. Should public key endpoint be blocked until true Ed25519 signature chain is wired end-to-end?
2. Should group/channel be explicitly labeled non-E2EE in product UX copy in all clients (Flutter + web)?

## Acceptance Checklist
- [ ] Architecture docs correspond to real code paths.
- [ ] Documentation set is structured and internally linked.
- [ ] Build instructions are executable.
- [ ] Security model documented with current limitations.
- [ ] No secret leakage in docs.
- [ ] PR includes review checklist and unresolved questions.
