# Pipecat Console route

## Goal

Move the Pipecat caller sample from `/` to `/pipecat-console` and use the root route as a compact
directory of the Console's browser-facing interfaces.

## Findings

- The same tracked React shell intentionally serves both the caller sample and `/transfer`; the
  React application selects the transfer page from `window.location.pathname`.
- Diagnostics, call inspection, operator sign-in, and the transfer page linked to `/` as shorthand
  for the caller sample. Those links must follow the sample when its route moves.
- The root directory should link only stable entry points. Per-call inspection detail and artifact
  routes require runtime identifiers and therefore do not belong in the static list.

## Implementation

- `/pipecat-console` now serves the existing React caller sample; `/transfer` is unchanged.
- `/` renders a server-owned semantic list linking the Pipecat console, transfer desk, operator
  call inspection, Vxpipe diagnostics, and Phoenix LiveDashboard.
- A separate `HomeController`, `HomePage`, and `home.css` esbuild entry keep directory rendering,
  presentation, and the existing sample asset boundary separate.
- All existing UI links that mean “voice console” now target `/pipecat-console`.
- Existing route-dependent tests were updated for the moved URL; no additional test case was added
  for this mechanical navigation change.

## Verification

- The existing React application file passes six tests.
- The focused existing Console endpoint, call-inspection, and diagnostics files pass 39 tests.
- All ten existing frontend tests pass, and `mix assets.deploy` emits the sample, shared LiveView,
  operator, diagnostics, and new directory bundles successfully.
- Chromium rendered `/` at 1440×1000 and 390×844. Both viewports had matching body, document, and
  viewport widths, no browser errors, and zero axe violations or incomplete findings.
- The rendered accessibility tree exposed all five expected interface links. Following the
  Pipecat link navigated to `/pipecat-console` and rendered the existing Create Room screen.
- The Impeccable detector reports no findings for the new page and stylesheet.
- Root formatting, warnings-as-errors compilation, the full umbrella test suite, unused-dependency
  checking, and strict Credo over 803 source files all pass.
