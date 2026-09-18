# Show telephony and simplify service selection

- User requested always-visible Telephony services with a clear optional label.
  Replaced the disclosure with a regular named section and preserved optional
  readiness behavior and provider actions.
- User then replaced the full-catalog search/list picker with a Service dropdown
  and inline credential fields. Options are grouped into AI providers and optional
  Telephony. Provider cards preselect their service. Selection is disabled during
  validation and changing it clears previous credential values.
- Updated existing tests first for each correction: telephony visibility red with
  1 failure, then green; dropdown red with 2 failures, then all 16 focused tests
  passing. A JSX edit syntax error was caught and corrected before the green run.
- Follow-up request uses three equal columns for Telephony, matching AI providers;
  both grids measure 362.656px per first card at 1440px. Mobile remains one column.
- Production routes and provider integrations remain unchanged. This is the
  Storybook review flow. Concurrent shared-copy changes in the working tree were
  preserved ("Connect AI and Telephony services...").
- Full frontend: 149 tests passing. TypeScript, ESLint, and Storybook build passed.
  Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed. Full umbrella run: 1,724 tests, 1 failure, 39 excluded.
- Browser inspection verified desktop/light/dark, mobile/light, visible Telephony,
  equal grid widths, blank Service dropdown, Deepgram API-key fields and Twilio's
  Account SID/Auth token fields. Escape restores focus. No browser errors observed;
  screenshots are in ignored `tmp/onboarding-storybook/`. Own browser closed.
- Root run seed 651292 exposed a billing lookup-start timeout. The owning-child file
  passed unchanged on retry (7 tests). The failure is outside the modified UI code.

- Further user correction: make service dialogs visibly modal using shadcn's
  treatment. Reviewed the official Radix/New York source: black 50% overlay,
  bordered solid surface, rounded corners and shadow. Matched these visual
  properties using existing theme tokens; existing dialog behavior is preserved.
  Source: https://github.com/shadcn-ui/ui/blob/main/apps/v4/registry/new-york-v4/ui/dialog.tsx

- Final modal inspection: dark desktop and light mobile at 390px show a 1px solid
  theme border, rgba(0,0,0,0.5) backdrop, and raised surface. Scroll width equals
  viewport width. The border change is styling-only; existing keyboard/modal
  behavior remains covered by the 16 focused interaction tests. Own browser closed.

- Final root `mix test --failed --seed 651292` passed the single billing-timeout
  test unchanged. The initial full run was not clean; retry evidence is retained
  in `tmp/onboarding-storybook/telephony-visible-final-retry.log`.
- Storybook build passed again after the final grid and border styles. Server
  remains on port 6006 for review. No commits or staging operations were performed;
  user-staged files were preserved.
