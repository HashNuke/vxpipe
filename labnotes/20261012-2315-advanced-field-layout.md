# Advanced field layout

- Applied the existing responsive-inline field layout to call-wide Advanced
  settings. A shared label width aligns the three inputs on desktop; mobile
  keeps labels above inputs. Help text remains on the next line across both
  columns, as requested.
- Shortened Maximum call duration (ms) to Max call duration (ms), including
  existing tests' accessible-name queries. No values or behavior changed.
- Mechanical layout/copy change: no new behavior test required. The existing
  settings suite passed (17 tests), along with TypeScript and ESLint. An initial
  test command at the workspace root matched no files; reran from Console assets.
- Inspected Storybook in headless Chrome at 1280px and 390px. Desktop input
  columns align; mobile labels stack, hints remain beneath, and controls fit.
  Layout detector and git diff whitespace check were clean.
- Umbrella completion gates passed: format check, warnings-as-errors compile,
  strict Credo, 3,574 tests with zero failures, and unused dependency check.
