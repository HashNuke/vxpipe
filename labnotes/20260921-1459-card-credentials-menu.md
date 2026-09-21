# Card credentials menu

## Checkpoints

- Started from `c1f21dd9` with a clean worktree. The request was to move credential removal out of the service dialog and into a vertical-ellipsis menu grouped with the card's edit icon.
- Wrote focused UI and production-flow tests before changing behavior. The card interaction test first failed because the group was absent; the production test first failed because no card menu existed. After moving the UI, the TypeScript check exposed the production modal's old removal callback, which was then moved to the card.
- Kept the existing `Use platform service` action in the tenant dialog. Inherited services and tenant overrides with a platform service do not show the removal menu. A card removal resolves its primary binding and credential ID before calling the scoped DELETE endpoint; while pending, card actions are disabled and the card reports progress. Rejection preserves the card and reports the error; a successful reload removes it and returns focus to the main region.
- Reused the existing Radix popover dependency. The first rendered browser pass showed transparent background and black text because a portal mounted outside `.vx-admin`, where theme variables are defined. Rendering the popover in the themed card tree corrected this. A second pass exposed a broad button-group selector shrinking the menu action; restricting that selector to direct child buttons restored the full click target and trash icon.
- Focused tests: 40 passed across the production service app, onboarding story, modal, and scoped story. Browser inspection in Chrome covered dark and light themes at 1440, 390, and 320 px. The menu rendered within the viewport, Escape closed it, and choosing Remove removed the story card.
- User review found the menu shadow too large. It came from `0 8px 24px var(--admin-line)`, which made a light halo in the dark theme. Replaced it with Tailwind `shadow-sm`, then inspected dark and light Chrome rendering. The computed shadow is a neutral 1–3 px shadow, and the menu keeps a compact border and destructive action color.

## Verification

- Console TypeScript and lint passed. The focused four-file suite passed (40 tests); the full frontend suite had passed (193 tests) before the final CSS-only shadow adjustment. Root formatting, compilation with warnings as errors, strict Credo, and unused-dependency checks passed.
- The first root `mix test` run reported one failure in `Vxpipe.CallEngine.Speech.TTSDeadlineTest` among 846 call-engine tests while Storybook and browser inspection were active. The exact deadline test file passed alone (4 tests). A second root run was stopped at the user's request not to run the entire suite for this UI change. No call-engine or speech source was changed in this checkpoint; the isolated full-suite miss is not evidence of instability caused by this UI change.
- `git diff --check` passed.
