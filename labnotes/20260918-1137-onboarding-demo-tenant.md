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
