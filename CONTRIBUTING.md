# Contributing

## Branching
- Use short-lived feature branches from `main`.
- Recommended naming:
  - `feat/*`
  - `fix/*`
  - `docs/*`
  - `security/*`

## Commit Style
- Keep commits focused and atomic.
- Prefer imperative subject lines.

## Pull Request Requirements
- Description of intent and scope.
- Files/areas changed.
- Risk assessment (security, data model, compatibility).
- Test evidence.
- Rollback notes for risky changes.

## Code Quality Checks

### Backend
```bash
cd backend
cargo fmt
cargo check
cargo test
```

### Flutter
```bash
cd apps/flutter
dart format lib test
flutter analyze
flutter test
```

### Frontend (if touched)
```bash
cd frontend
npm ci
npm run lint
npm run build
```

## Security Checklist (mandatory)
- No secrets in code, docs, or commit history.
- No real fingerprints/hashes in docs.
- No plaintext private key handling outside secure storage.
- Auth-sensitive changes include negative tests.
- E2EE behavior changes include protocol/compatibility notes.

## Documentation Checklist
- Update relevant docs when changing:
  - API routes
  - auth/session behavior
  - crypto primitives/flows
  - build/runtime flags

## Suggested CI Baseline
- Markdown lint:
  - `npx markdownlint-cli2 "**/*.md"`
- Secret scanning:
  - `gitleaks detect --source .`
- Basic SAST:
  - `semgrep --config auto`
- Build/test jobs for backend + flutter.

## Git Flow
1. Create branch.
2. Implement + test.
3. Rebase onto latest `main`.
4. Open PR with checklist.
5. Address review comments.
6. Merge after green checks.
