# Onboarding Demo Tenant

## Objective

Add a first-run Console flow that creates DemoTenant, lets the operator choose providers, validates
their credentials, records when validation succeeded, and optionally installs sample call specs.
The user required Storybook design before production endpoint work.

## Checkpoint: Storybook surface

- Existing Storybook had Services and Full journey stories, but no dedicated first-run flow.
- Added `vxpipe_console/Onboarding` with creating, provider selection, credential entry, validating,
  provider rejection, ready/loading/complete samples, unavailable, light and narrow states.
- Kept Google Vertex AI out of the chooser because the current shared form models it incorrectly as
  one API key. Vertex should return only after project/service-account fields exist.
- Reused the existing provider logos and credential form. Added a `showCancel` option so onboarding
  does not render a no-op Cancel action.
- The first desktop render exposed an empty colored grid cell for the fifth provider. Replaced the
  gap-backed table treatment with individually bordered cards and rechecked desktop/mobile.

## Test evidence

- Red: focused Vitest initially failed because `OnboardingPage` did not exist.
- Green: `npm test -- --run src/admin/OnboardingPage.test.tsx` — 4 tests, 0 failures.
- `npm run check` in Console assets — pass.
- `npm run lint` in Console assets — pass.
- Browser: Chrome-rendered Storybook inspection at 1440×1000 for provider selection and 390×844
  for credential entry; headings, controls, responsive stacking and the corrected odd-card layout
  were inspected.

## Decisions pending backend work

- Provider validation must happen before replacing a stored credential, using a non-billable
  provider-owned authentication endpoint behind an injectable boundary.
- `last_validated_at` is evidence for the exact credential material saved. Replacing that material
  invalidates old evidence; a later call can still fail for model/voice permissions or expiry.
- The repository currently has one managed development `SampleCall`, not the requested checked-in
  three-entry onboarding catalog. The catalog remains a separate implementation checkpoint.

## Checkpoint: provider validation evidence

- Added a Calls-owned validator port and separate validated create/update workflows. Existing trusted
  provisioning remains unvalidated and stores no timestamp.
- Console operator writes now validate before persistence. Provider rejection returns an actionable
  422; timeout, rate limit, transport and upstream failures return a retryable 503.
- Added read-only probes for Google model listing, Deepgram project listing, Zenmux model listing,
  Telnyx Call Control application listing and Twilio account fetch. Retries and redirects are off.
- Added nullable `provider_credentials.last_validated_at`. Successful validation evidence is stored
  atomically with the encrypted credential version and returned only as safe metadata.
- Updated the frontend API projection to preserve `lastValidatedAt` for the onboarding integration.

### Test evidence

- Calls operator administration: 16 tests, 0 failures.
- Persistence provider credential store: 11 tests, 0 failures after the new migration.
- Console services endpoint and validator: 8 tests, 0 failures.
- Frontend admin API parser: 11 tests, 0 failures; TypeScript check passes.
- Affected full suites: Calls 107, Persistence 153, Console 160 and frontend 129 tests, all passing.

## Checkpoint: durable DemoTenant identity

- Added an installation setup record that binds one generated tenant identity independently of its
  editable display name. An existing unrelated tenant named `DemoTenant` is never adopted.
- The persistence transaction creates the tenant and singleton binding together. A retry returns
  the existing binding; a losing singleton insert rolls back its candidate before resuming.
- Added a narrow operator-authenticated, CSRF-protected endpoint. It returns tenant metadata only
  and does not create an otherwise orphaned plaintext tenant API key.
- Also corrected the admin service projection to carry the previously persisted
  `last_validated_at` value through the real persistence adapter.

### Test evidence

- Calls suite: 109 tests, 0 failures.
- Focused Persistence demo/admin store: 9 tests, 0 failures.
- Console onboarding endpoint: 2 tests, 0 failures.
