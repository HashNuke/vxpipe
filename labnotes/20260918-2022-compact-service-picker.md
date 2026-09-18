# Compact service picker

## Scope and decisions

- User authorized the Storybook redesign: remove capability cards and explanatory
  phrases, compact featured-service cards, explicit AI providers and Telephony
  headings, a separate full-catalog Connect a service button, connected-service
  Manage cards and one readiness message by Continue.
- Picker searches names and capability labels, groups AI/telephony, shows no-match
  feedback, and transitions to credentials inside the same focus-trapped dialog.
  Returning to the picker preserves search. Existing secrets are never prefilled.
- Current runtime has no speech-to-speech provider integration. Dedicated preview
  stories inject that capability into the Google fixture only, with an explicitly
  illustrative model name. Base provider catalog and production code are unchanged.
- Voice conversation accepts either pipeline or audio preview; handoff recipes
  retain pipeline requirements. Provider catalog is passed through readiness,
  resumption, recipe availability and model preview to avoid inconsistent states.
- Removed the unused capability component and its styling. Existing tenant/API-key
  state, default Demo name changes and unrelated worktree edits are preserved.

## Verification

- Updated behavior tests before implementation: 9 failing, 7 passing. New checks
  cover full-catalog search, empty results, dialog focus, connecting unfeatured
  services, audio readiness and per-recipe blocking, and optional telephony.
- Focused implementation run: all 16 tests passed. Full frontend: 149 tests across
  25 files passed. TypeScript, ESLint and Storybook production build passed;
  existing large-chunk build advisory remains.
- All root completion checks passed: format, warnings-as-errors compile, strict
  Credo, unused dependencies, and 1,724 umbrella tests with zero failures
  (39 excluded). Log: `tmp/onboarding-storybook/compact-services-umbrella.log`.
- Rendered Chrome inspection covered 1440px desktop/dark and 390px mobile/light,
  connected services, picker/search/empty results/credential entry, plus the audio
  readiness and per-recipe preview at 360px. No horizontal overflow at 360px and
  no browser errors were observed. Screenshots are under ignored
  `tmp/onboarding-storybook/`. Own browser session closed after inspection.
- Initial Storybook restart raced the previous process releasing port 6006.
  Restarted successfully after release; `bin/dev` was untouched. Generated startup
  log was moved to the ignored task-artifact directory.
- A browser batch selector containing spaces stalled; canceled that inspection
  command and used unambiguous CSS selectors. Recipe preview was confirmed with
  a DOM click after the automation click did not activate it; unit interaction
  tests independently cover the same preview and provider selection.
- No production routes, providers, credentials or runtime API calls were added.
  Storybook remains running for user review.
