# Compact voice picker

## Request and decisions

- Compact the reviewed modal, make metadata look like tags, remove the dedicated
  count and enclosing list border, and align title with provider/model.
- Use one searchable dropdown for provider-declared single/multiple select filters.
  Preserve provider cardinality: Cartesia language is scalar, ElevenLabs is an array.
- Stage search/filter changes until Apply filters or search submission. Clear is
  staged too. Show unapplied, updating and updated states; reset pagination on apply.
- Storybook still uses sample catalogs. The picker delegates the complete query to
  the client; authenticated provider adapter integration remains proposed work.

## Implementation and evidence

- Red: focused picker suite failed 3/5 tests as expected: search requested immediately,
  multiple languages had no dropdown, and Apply filters did not exist.
- Green: 5/5 focused tests pass, including staged query requests, reset of pagination,
  searchable scalar/multiple language mapping, stale response rejection, staged
  voice selection, ID-only persistence, focus restoration, retry and read-only state.
- The first searchable dropdown test exposed cmdk's generated label taking precedence
  over the input's aria-label. Giving Command its label fixes the accessible name.
- Console TypeScript and ESLint pass.
- Browser review and root completion checks completed; evidence below.

## Browser and build verification

- Chrome at 1280×900 and 1440×900: compact rows/tags and one-line header render
  correctly. Cartesia language search narrows options; choosing Hindi leaves all
  loaded rows intact until Apply, then displays only Anaya and Results updated.
  Search submission with Enter produces the expected empty state.
- Chrome at 390×844 in light theme: ElevenLabs language dropdown supports searching
  and choosing English plus Hindi without inline checkboxes. Header wraps when
  needed; footer remains visible and filter/results content scrolls.
- Main call-spec page: chose Cartesia in call defaults, opened the updated modal,
  selected Rowan and confirmed the inline field updates after Use voice.
- Removed an extra toolbar gap noticed in rendered review and confirmed on the
  full page. Browser session closed; Storybook remains running on port 6006.
- Screenshots: `vxpipe-compact-voice-desktop.png`,
  `vxpipe-compact-language-search.png`, `vxpipe-compact-voice-filtered.png`,
  `vxpipe-compact-voice-mobile.png`,
  `vxpipe-compact-voice-mobile-languages.png`, `vxpipe-compact-voice-page.png`.
- All 552 Console frontend tests (71 files), TypeScript, ESLint, and Storybook
  production build pass. Build retains existing chunk-size warnings.
- Root format, compile with warnings as errors, Credo strict, and unused-dependency
  checks pass. Full umbrella tests reproduce the existing Ortex macOS NIF loading
  error (mis-aligned LINKEDIT string pool); final results below.

## Review follow-up

- User asked to reduce the prominence of voice IDs. Softened the existing muted
  text color (85% in light theme, 70% in dark); retained the smaller size and full ID.
- Verified ElevenLabs in both themes with Chrome. Screenshots:
  `vxpipe-voice-muted-id-dark.png`, `vxpipe-voice-muted-id-light.png`.
- Clarified that the three ElevenLabs entries are fixtures. Load more is shown only
  when the client supplies a next cursor; user acknowledged the sample-data scope.

## Further UI review

- Reduced voice filter fields, search and action controls to 12px text and 32px
  height; dropdown search/results use the same smaller text.
- Put Model type beside its dropdown in both call defaults and agent Models.
  Added an opt-in inline layout to the shared field, preserving labels and help/error
  associations. Removed the requested global model-type explanatory sentence.
- These are styling/copy changes: no new behavior test required. Existing focused
  suites for voice picker, default models and agent inspector pass (26 tests), as
  do TypeScript and ESLint.
- Full root test run completed with exit 2: 6 Call Engine failures from Ortex's
  macOS NIF loading error, plus Console's configured ElevenLabs speech readiness
  failure in the same environment. Gateway passed 595 tests; Console ran 250 tests.
  MCP, Providers, Agent Runtime, Calls, Artifacts and Persistence passed. Log:
  `vxpipe-compact-voice-mix-test.log`. No unrelated native-library edits made.
- Final rendered checks: smaller filters at 1280×900 and 390×844; Model type inline
  in call defaults and agent Models on desktop, and call defaults in the mobile
  sheet. Waited for sheet transition before the final mobile capture; label and
  control centers both align at y=300 with the control fully within the viewport.
  Evidence: `vxpipe-voice-small-filters.png`,
  `vxpipe-voice-small-filters-mobile.png`,
  `vxpipe-model-type-inline-defaults.png`,
  `vxpipe-model-type-inline-agent.png`, `vxpipe-model-type-inline-mobile.png`.
- Final diff whitespace check passes. No commits created; existing work preserved.
