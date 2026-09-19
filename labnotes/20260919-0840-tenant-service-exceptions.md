# Tenant service exceptions

- Started after reviewed A3 HTTP authoring commit `3ee3e4f` and its complete
  1,754-test umbrella run (zero failures, 40 exclusions).
- Calls/Console red tests demonstrated the missing authorized tenant policy
  workflow/endpoint and tenant creation discarding an explicit credential name.
  Added the operator-only boundary and CSRF-protected exact provider/name policy
  route. Named tenant creation now preserves the supplied name. Focused tests pass.
- Frontend red tests covered override/save, disable/restore, dormant tenant-row
  replacement, missing-override placeholders and policy/reload failures. The first
  implementation passes all six tests and the 176-test frontend suite, TypeScript
  and ESLint. Policy writes reload persisted state before showing success.
- A further red test found a primary tenant-only binding mislabeled as an override
  when a different named platform binding existed. Restrict primary-card platform
  metadata to exact primary names; modal restoration also matches the exact name.
- Preserve the approved setup design. Starting an override is only a local draft;
  credential validation and persistence activate it atomically. Cancel/rejection
  preserve the previously saved policy; active failed/missing overrides remain
  unavailable and never borrow platform credentials or saved-field placeholders.
- Reuse dormant tenant credential IDs on renewed overrides; never PATCH a platform
  credential through the tenant endpoint. Disable/restore retain dormant rows and
  affect future preparation, preserving already-initialized client ownership.
- Final focused results: Calls 115 tests, Console 178 tests (one excluded), frontend
  177 tests in 29 files; zero failures. TypeScript, ESLint, asset/CSS builds, root
  format, warnings-as-errors compile, strict Credo and unused-dependency checks pass.
- Chrome at 1440×1000 and 390×844 exercised a real operator session and encrypted
  PostgreSQL credentials with a synthetic provider validator. Verified two inheriting
  tenants and a third override, rejected validation recovery, disable across fresh
  server restart, restore followed by replacement preserving the same tenant ID,
  named override creation, missing override without fallback/readiness, empty inputs
  without false saved placeholders and explicit restore recovery. No upstream was used.
- One browser reload overlapped the owned server restart and stalled a browser wait.
  Stopped only the owned waiting CLI processes, reopened after health returned, and
  completed the persisted-state check. Offscreen named buttons required explicit
  `scrollintoview` before the CLI's pointer click. Neither required product changes.
- Visual inspection found no new overflow or layout issue in the existing design.
  Removed the owned browser/server, disposable database and private session file.
  The serial umbrella run completed 1,757 tests, one failure, 40 exclusions with
  seed 772211. The unchanged five-participant handoff test timed out waiting for
  250 Hz audio at line 518 after listener reconnection. An isolated rerun failed
  later at line 666, expecting ordered cue/conversation audio. Root acceptance
  remains open; no cause or fix is claimed, and no media assertion was weakened.
- Integration review found the older `/admin/onboarding` entry and `DemoSamples`
  still use tenant-only service inventory. Added an explicit B3 delivery step for
  those consumers so the required effective-service onboarding work stays tracked
  without enlarging this tenant-policy checkpoint. The scoped setup page's readiness
  has passed; inherited sample installation through the older entry is not yet claimed.
- Pre-commit review covered installation-only authority, CSRF and closed policy
  inputs, exact provider/name selection, dormant ID reuse, empty secret fields,
  cancelled/unmounted requests and durable reload before readiness. The named-binding
  label correction is regression-tested. No remaining service-policy finding;
  the native umbrella verification failure above remains unresolved.
  A small saved-field mapping refactor then passed the seven focused frontend tests,
  TypeScript and ESLint again; it makes no rendered-layout change.
