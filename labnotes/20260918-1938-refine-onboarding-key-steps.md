# Refine onboarding key steps

## Scope and decisions

- User requested Storybook review only: one shared tenant onboarding flow with
  Setup services, Create API Keys, and Setup Call Specs as distinct steps.
- Service copy identifies the created tenant without Demo-specific wording. No
  samples or sample prompts appear on the services page. Telephony stays optional.
- The second step offers Calls or Full tenant access, a key name, creation/error
  states, one-time value display, clipboard action, and existing-key metadata.
  Keys are explicitly nonfunctional Storybook fixtures. No issuance endpoint,
  database mutation or production route changes are part of this checkpoint.
- Third-step recipe actions say Load sample / Open sample. Keys are optional for
  continuing through the operator-owned prototype; they are for backend callers.

## Permission evidence

- `apps/vxpipe_calls/lib/vxpipe/calls/administration.ex` validates only admin/calls
  and checks exact membership for authentication: neither grant implies the other.
- `admissions.ex`, `inspections.ex`, `call_read_access.ex` and
  `billing_enrichments.ex` require calls. Gateway `call_admission.ex` authenticates
  calls before preparing calls, participant sessions and join tokens.
- Calls choice = calls. Full tenant access = admin + calls. Both remain tenant
  scoped; neither grants installation/platform authority.
- Admin is a supported grant, not proof of a general tenant-admin HTTP API.
  Key issuance/revocation currently use trusted OTP/CLI workflows; the Console's
  installation operator has separate authority. Copy must not promise particular
  unimplemented admin endpoints or tenant API-key management via that key.
- Persistence validates key names up to 256 characters and stores a digest. CLI
  issuance returns the plaintext once; the API cannot retrieve it later.

## Tests and implementation evidence

- Updated focused behavior tests first: red with 11 failures and 2 passing before
  the new three-step flow existed. Coverage adds shared tenant copy, breadcrumbs,
  exact step order, both key grants, one-time reveal, metadata retention and
  isolation when creating another tenant.
- Prototype keeps only key metadata in per-tenant progress. Leaving the key step
  clears its revealed value. Pending issuance disables navigation to avoid writing
  an asynchronous result into a different tenant's state.
- Focused onboarding tests: 13 passing. Full Console frontend: 146 tests across
  25 files passing. Type checking, ESLint and the Storybook build passed; the build
  retains the existing large-chunk advisory.
- Rendered Chrome review covered desktop services, both key choices, creation,
  copying and third-step recipe cards; mobile services, key errors and one-time
  reveal at 390px and 360px. No horizontal overflow or browser errors observed.
  Screenshots are under ignored `tmp/onboarding-storybook/`. The inspection's
  `onboarding-keys` browser session was closed; Storybook remains on port 6006.
- A live Storybook reload during editing invalidated browser element references.
  Closed the inspection session and reopened direct fixture stories; the final
  inspection completed after source edits stopped.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed.
- Full umbrella run (seed 298766): 1,724 tests, 1 failure, 39 excluded. The gateway
  test `adopts the actual prepared telnyx decoder` returned `{:error, :unavailable}`
  while preparing audio. Its owning-child file passed unchanged on same-seed
  retry (13 tests), and root `mix test --failed --seed 298766` passed (1 test).
  This Storybook checkpoint changes no audio implementation. Logs are retained
  under ignored `tmp/onboarding-storybook/key-steps-umbrella*.log`.
