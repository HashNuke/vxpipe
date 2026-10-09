# Preserve source integers

## Scope and decision

User authorized fixing review finding 1 and requested explanation of finding 2.
Leave the `new` ID collision and its existing failing regression unchanged. No
commit requested for this follow-up. Existing review tests and unrelated cache
repair labnote are preserved. This checkout was set up during the prior milestone.

Use lossless-json 4.3.1 at the source boundary with a custom number parser: integer
tokens outside the safe range become native bigint. All source serialization
emits ordinary unquoted JSON numbers. Keep built-in number behavior for safe
integers and floats. Updated source-aware serialization in dirty checks, retained
backend errors, export and API writes; structured numeric fields and schema
validation accept the same representation. Do not convert integer values to
strings or make valid documents read-only. Dependency added only to Console
assets with its exact package lock entry; no backend contract changes.

## Red and green evidence

- Re-ran original editor-api regression: 1 failed, 3 passed; outbound enum value
  was 9007199254740992 instead of 9007199254740993.
- Added source/form integration cases before implementation: 4 failed, 1 passed,
  showing corruption on read/export, negative and larger option values and field
  display. Initial command accidentally used root Vitest scope and found no
  tests; reran from Console assets for the actual red evidence.
- Original regression plus integration and existing validation cases pass (83
  tests). TypeScript and lint pass.
- Added a separate red schema-length contract: backend accepts arbitrarily large
  non-negative limits, while old client validation rejected them at the JS safe
  range. Updated validation without relaxing rejection of negative values.

## Browser preparation

Added a Large Integers page story. Existing dev Storybook on port 6006 fails to
load current modules (stale long-running Vite process); leave that server alone.
Chrome requires --no-sandbox on this host. Use a fresh build/server for the bounded
rendered check. No live services or credentials accessed.

## Verification progress

- Full frontend run: 509 passed, 1 failed. The sole failure is the untouched
  `new` ID collision review regression. After adding the separate length-bound
  case, reran API/integer/validation files: 84 passed. Final TypeScript and lint
  pass, as does git diff --check.
- Fresh Storybook build passed. Agent-browser Chrome inspected the Large Integers
  story at 1440x1000 and 390x844: exact DOM/input digits, editing a negative large
  enum, saving the draft, and exact source JSON all passed. No page errors or
  document overflow (390px document at 390px viewport). Screenshots are temporary
  verification artifacts. Chrome's numeric accessibility-tree value rounds large
  spinbutton numbers, so verified actual input string values and screenshots as
  well as exported JSON. Browser closed after the bounded pass.
- Root format, warnings-as-errors compile and strict Credo passed. The initial
  long-running shell received SIGTERM (143) during umbrella tests without a test
  failure report; the remaining gates were not run by that interrupted shell.
  Restarted tests and the remaining gates in an isolated tmux session to keep the
  runner alive. No speech/source-cutover state-machine code changed; no Lean lane
  required. No live tests used.

A bounded browser follow-up addressed the numeric accessibility-tree rounding:
added an explicit aria-valuetext from the exact input string. First extended the
field regression and observed the expected missing-attribute failure, then made
it green. All 84 focused tests pass again. Rebuilt Storybook and confirmed the
exact positive/negative aria-valuetext strings in Chrome with no page errors.
The temporary preview server and browser were stopped; existing previews remain.
Final TypeScript check passes after this change.

## Final outcome

All five required umbrella gates pass: format, warnings-as-errors compilation,
strict Credo, 3,460 tests with zero failures (120 excluded), and unused dependency
lock check. Production assets build also passes. Gateway took 476.1 seconds,
consistent with its 487.2-second baseline; the test process completed normally.
The tmux runner exited after its checks. No live tests or Lean lane ran.

Final frontend evidence: 509 passing tests and the one intentionally unfixed
`new` ID regression in the broad run; 84 focused API/integer/validation tests pass
after the additional length-bound/accessibility cases. The six integer tests
were rerun after correcting a fixture capability key and all pass. TypeScript,
full lint plus targeted lint after the final accessibility edit, and diff checks
pass. Work remains uncommitted, preserving all preexisting review/unrelated files.
