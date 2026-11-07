# Connect listed static forms

- Builds on `71f7b0ef`, the independently reviewed listed static backend with all
  five root gates passing (4,914 tests, zero failures; seed 780141).
- Reuse the existing production MCP dialog and directory page. Listed creation
  takes a reference and fixed display configuration; saved management takes its
  accepted snapshot. Neither mode exposes URL/authentication/header-name selectors.
- Preserve the incumbent Console controls, masked secret fields, modal tabs and
  responsive layout. Optional notes render as plain text and independent setup /
  documentation links are validated before display.
- Red evidence: three form failures (unlocked form, missing listed title/fields,
  no specific stale-listing recovery), two parser failures (dropped configuration
  and unsafe/mismatched metadata accepted), two directory action/permission
  failures, and one backend inventory eligibility failure before implementation.
- Green so far: all 68 focused Integrations frontend tests and eleven backend
  inventory tests pass. Listed OAuth/forms and retained-ID recovery remain open;
  OAuth listed Connect stays disabled with a visible explanation in this slice.
- Independent adversarial source review is clean, including the subsequent style
  scope fix. No actionable findings were reported.
- Initial rendered inspection found the production dialog missing the ancestor
  class required by its imported MCP styles: inputs were unstyled and the desktop
  form overflowed horizontally. The dialog now supplies that existing scope;
  headings and notes also wrap. This is recorded as a completed milestone fix.
- Chrome confirmation at 1280×900 and 390×844 shows contained forms and controls.
  Exercised API-key create/replace, bearer/Basic/anonymous forms, saved tools during
  a simulated directory outage and read-only controls. Local Storybook fixtures
  use no provider requests. Closed the owned browser session after inspection.
- One automation wait matched the existing Connected navigation before mutation
  completion; waiting for the actual Manage action resolved it. The form itself
  completed successfully; this was a browser-script synchronization issue.
- Full frontend: 1,018 tests in 135 files pass. After the style correction, all
  68 focused Integrations tests pass again. TypeScript passes; ESLint reports only
  the pre-existing SetupDialog hook dependency warning. Formatting, compilation,
  strict Credo and unused dependencies pass. Root suite: 4,915 tests, zero failures,
  201 excluded, seed 342196. Independent exact-index review of all sixteen staged
  paths is clean. All five root gates pass; the milestone remains open for listed
  OAuth and broader acceptance work.
