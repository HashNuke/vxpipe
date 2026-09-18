# Simplify key copy

- User selected the exact access labels **Create & Join Calls** and **Full Access**.
- Updated the options and created/existing key indicators through shared metadata.
  Full Access description says "Access all operations for this tenant."
- Removed raw scope badges from selection and key reveal; underlying calls/admin
  grant mapping is unchanged. This remains a Storybook prototype.
- Updated existing key creation tests before implementation: both label scenarios
  failed as expected; all 13 onboarding tests passed after the copy change.
- Full frontend suite: 146 tests passing. TypeScript and ESLint passed. Root
  format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed.
- Chrome inspection confirmed both options on desktop/mobile and Full Access on
  the created-key indicator. Raw scope badges are absent. Own browser session
  closed; Storybook remains available. Screenshots are in ignored
  `tmp/onboarding-storybook/key-copy-*.png`.
- Root test run: 1,724 tests, 2 failures, 39 excluded. Seed 638477 exposed a live-inspection
  participant-not-found failure, which also failed in its unchanged owning-child
  file on retry, plus the previously observed gateway audio-preparation failure. The gateway
  file passed unchanged on retry (13 tests).
  No backend files were changed for this copy task.
- Follow-up discussion only: user wants capability names without explanatory
  phrases or repeated non-action text. Proposed readiness accepts either a
  supported speech-to-speech path or STT + LLM + TTS; per-recipe requirements stay
  on the Call Specs page. No service-screen redesign implemented in this task.

- Latest proposed direction removes the capability cards entirely: compact featured
  service cards with tags, a separate Connect a service button opening the full
  provider picker, and one readiness message near Continue. This supersedes the
  earlier two-row capability-summary proposal; no layout changes made yet.

- Final root `mix test --failed --seed 638477` passed both failed tests unchanged
  (one CallEngine test and one Gateway test). The initial full run was not clean;
  same-seed retry evidence is in `tmp/onboarding-storybook/key-copy-final-retry.log`.
