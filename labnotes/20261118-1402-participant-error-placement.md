# Participant error placement

- The participant rename control registers the participant object path. Prefix-based matching incorrectly assigned hidden Models errors to that control and pulled them into unrelated tabs.
- Added exact issue-path matching for rename controls. Other fields retain parent/child fallback; tab inclusion uses the same matching rule. Actual key errors still appear on the rename control.
- Regression initially failed because Participant key had aria-invalid=true for a model error on Prompt. All 415 editor tests now pass, including tab switching, Models issue count, and actual key-error placement. TypeScript passes.
- Chromium desktop inspection confirms Model owns the error and Prompt has no invalid key or stray inline model error. Mobile inspection confirms the same error behavior; the existing fixed-width sidebar clips at 390px, outside this correction's scope.
- Format, warnings-as-errors compilation, strict Credo and unused-dependency checks pass. All 1,158 frontend tests pass; ESLint has zero errors and the existing SetupDialog hook warning. The umbrella attempt reported an unrelated STSMCPRoomTest readiness assertion (`:not_ready`); isolated rerun with the same seed 657359 passes. Stopped the broad run after that failure; no full umbrella pass is claimed.

## Release verification

- Committed implementation as `245020cea3655c8d99cf95ecf5b6eb1ea67c18eb` before building production assets and release; both succeeded.
- Previous image retained as `vxpipe:before-key-placement-20261118`. Deployed image `sha256:165e6441337b73aba942ef581384ffaff46625634a0e671fbb6050692c6b9bd0` through the existing systemd migration/restart workflow.
- Running container OCI revision matches the implementation commit. Service is active/running with Result=success and NRestarts=0. Local and public health endpoints return `ok`; served admin JavaScript and CSS hashes match the assembled release.
