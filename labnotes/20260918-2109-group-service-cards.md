# Group service cards

## Request and decisions

- Replace recommended/unconnected provider cards with a persistent Connect a service card at the end of each AI providers and Telephony grid. Keep connected cards in their own group, including when every provider is connected.
- Keep three desktop columns, one mobile column, and visible optional telephony. Each add card opens the existing modal with a dropdown scoped to its section.
- Follow-up: remove the bottom capability/readiness text from step 1. Preserve capability-based Continue availability.
- Follow-up: use the exact telephony explanation “Browser-based calling does not need telephony. Phone calls need a telephony service.”
- Follow-up: correct heading hierarchy: Setup services h1 (20px), AI providers / Telephony h2 (16px), tenant-created confirmation as 14px status with 18px icon. Focused heading test failed before the change (1 of 17) as expected.
- Follow-up: present the tenant-created status in a bordered, subtly green success alert container while retaining the smaller type and semantic status role.
- Storybook prototype only; preserve the user’s staged changes and tenant copy. No commits or bin/dev management.

## Verification

- Initial root npm test command did not include console tests; reran from console assets.
- Red: updated focused suite failed 8 of 17 tests for missing group add cards, recommendation cards still present, and footer text still present.
- Green: all 17 focused tests pass after implementation. Covers empty/all-connected grids, last-position add cards, scoped dropdowns, draft reset, focus restoration, optional telephony, and voice readiness.
- Final TypeScript and lint checks pass. Full console suite: 150 tests pass. An intermediate concurrent run timed out in AdminJourneyStory; that file plus onboarding passed unchanged (23 tests), then the full suite passed unchanged.
- Storybook production build passes, with existing chunk-size advisories.
- Headless Chrome: checked empty dark and connected light states at 1440px and 390px. Verified AI and telephony dropdown scoping and connection actions; connected cards stay in the correct section and add cards stay last. Checked updated headings, exact telephony copy, removed readiness text, alert border/tint, and mobile stacking. Screenshots under ignored tmp/onboarding-storybook/group-*.png. Closed only the group-cards browser session; Storybook remains running.
- Browser workaround: used batch stdin arrays for selectors containing spaces; waited for ongoing commands to complete. Initial color mixing in oklch shifted pale success colors toward pink/blue; switched the alert blends to oklab and rechecked light/dark screenshots.
- Root format, compile with warnings-as-errors, strict Credo, and dependency unlock checks pass. Full umbrella run (seed 331232): 1,724 tests, five failures, 39 excluded. Failures: CatalogRefresherTest (two), EgressReadinessTest (one), CallIngressTest (two). All five passed unchanged with `mix test --failed --seed 331232 --trace` (serial trace replay); no backend changes were made for these failures. Retry evidence: tmp/onboarding-storybook/group-cards-umbrella-retry.log.
- Final diff whitespace check passes; existing staged/unstaged changes preserved.
