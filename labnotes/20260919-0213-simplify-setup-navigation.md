# Simplify setup navigation

- The user questioned Back buttons inside onboarding step content because the
  persistent step navigation already provides the same destinations. Removed
  Back to services and Back to API keys, their unused callbacks, icons and CSS.
  Kept forward Continue actions and contextual missing-service recovery.
- Updated the existing journey test to return through the setup navigation and
  require the redundant Back actions to be absent. Red: the focused test failed
  on the existing Back to API keys button before implementation.
- Investigated the separate Telnyx Continue question: the catalog displays
  STT/LLM/TTS but has no Telnyx sample capabilities or default models. Readiness
  checks require both. Chrome reproduced saved Telnyx cards with disabled
  Continue; existing onboarding/scoped tests passed (29 tests). This is the
  documented runtime-support gate, not a failed connection or inheritance bug.
  No provider support or readiness policy was changed in this checkpoint.
- Reviewed the platform/tenant service plan against current credential structs,
  persistence schema and Console endpoints: the first inherited-provider backend
  slice is specified, while storage/readers, scoped webhook routing and production
  onboarding integration remain unimplemented. Telnyx AI integration is separate
  work; implementing credential inheritance alone will not enable it.

## Verification

- Focused navigation test passes after removal. Its first post-change run exposed
  a test-locator difference: jsdom joins the step number and label without a
  space. Matching the label within the named navigation fixed the locator.
- Console frontend: 169 tests across 28 files pass; TypeScript and ESLint pass.
- Headless Chrome verified navigation from services to API keys to call specs
  and back through the tabs at 1440x1000 and 390x844. Screenshots of both changed
  pages show no redundant Back action or leftover gap. Evidence is under ignored
  `tmp/onboarding-storybook/setup-navigation-*.png`. Browser session closed.
- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict` and `mix deps.unlock --check-unused` pass. Root `mix test`
  passes: 1,724 tests, zero failures, 39 excluded (seed 166539). The existing
  gateway suite took 345.6 seconds; no rerun or backend changes were needed.
  The run is captured in ignored `tmp/setup-navigation-mix-test.log`.
- Final diff/whitespace inspection passes. Pre-commit review found no remaining
  callbacks, CSS references or navigation regressions. The user subsequently
  requested reviewed checkpoint commits; this cleanup is its own checkpoint.
