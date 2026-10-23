# Morse provider labels

Updated the displayed provider names to **MorseCode API** and **MorseCode
Local** in the model catalog and Console. Service setup, saved service
inventory, onboarding fixtures, and the call-spec editor now use the requested
names. Provider identifiers, adapter modules, and model names stay unchanged.

The call-spec editor previously displayed raw provider identifiers, so its
provider choices now map the two Morse identifiers to their display names.
Other providers retain their existing presentation.

This is a presentation-only change. Updated existing expectations without
adding label-specific tests.

## Verification

- Focused UI tests: 51 passed across the API mapping, onboarding, and capability
  field suites; ESLint passed.
- Formatting, compilation with warnings as errors, strict Credo, and unused
  dependency checks passed.
- Production asset build passed, including TypeScript, Tailwind, and esbuild.
- Inspected the rendered service connection modal and call-spec provider choices
  with agent-browser in Chrome. Both names appear correctly; selecting each
  provider preserves its model choices. Checked desktop (1280x900) and mobile
  (390x844); provider labels fit.
- Full umbrella suite passed: 3,876 tests reported across ten applications,
  zero failures (131 excluded by the default tags).
- Verification uses the default local suite, which excludes `live_providers`
  and integration tests. No live-provider runner was invoked.
