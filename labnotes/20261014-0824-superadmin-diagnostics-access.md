# Superadmin diagnostics access

## Decision and implementation

- Diagnostics already used named-user sessions, but admitted Admin accounts via
  the built-in diagnostics.read grant. User requests Superadmin-only access.
- Require account_kind == :superadmin for diagnostics browser routes/return paths,
  socket connection and repeated LiveView authorization. Align route requirement
  metadata and its API evaluator with the same account-kind requirement.
- Preserve enabled flag, private-host guard and current-session resolution.
  Existing grants cannot bypass the account-kind gate.
- Update route inventory and authorization documentation.

## Verification

- Added tests denying Admin/member HTTP routes, socket and direct LiveView mount
  even while retaining Superadmin fixture grants. Added demotion during an open
  stream. Red run: 14 tests, 2 failures (Admin admitted; stream not redirected).
- Implementation green: 42 diagnostics, endpoint and authentication tests pass,
  including existing Superadmin LiveDashboard and revocation coverage.
- First test-edit command used the child directory with root-relative paths and
  did not edit files; corrected working directory and reran the red suite.
- No visual component changes. HTTP and connected LiveView boundaries exercised
  through Phoenix endpoint/LiveView tests.
- Root format, warnings-as-errors compile, strict Credo and unused dependencies
  passed. Full suite: 3,790 tests with one unrelated WebRTC 250 Hz audio timeout
  in the five-participant handoff test. That test passed on isolated rerun
  without code changes; all other suites passed, including 303 Console tests.
