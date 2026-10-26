# Tenant page breadcrumbs

## Requested behavior

- Tenant-scoped Storybook pages use Tenant > Section > Page breadcrumbs.
- Installation-wide pages use Settings as the root, without inventing a tenant.
- Remove top page Back controls when breadcrumbs provide the return path. Existing
  Cancel/return actions remain with form actions; sidebar tenant switching and
  modal step navigation are outside this page-header change.
- Service directory header order is title, search, Connect other MCP on desktop;
  mobile stacks those controls in the same order. Capabilities remain tags.

## Implementation

- Added a shared breadcrumb presentation and opt-in Storybook navigation context.
  Workspace/navigation stories supply tenant identity and fixture navigation;
  dynamic service and API-key pages own their additional breadcrumb segments.
- Applied the pattern to tenant lists/details, services and the directory, call
  history, API-key forms, users/roles, installation settings and call-spec editor.
- Shared live components retain their previous defaults without the preview
  context. No backend, OAuth, persisted settings or service APIs were changed.
- Editor breadcrumb departures use the existing unsaved-changes guard.
- Existing legacy key and service scenarios remain simulated.

## Verification so far

- Seven integration tests failed against the old breadcrumb/navigation workflow,
  then passed. A focused editor test failed before its breadcrumb was introduced,
  then passed with confirmation required before leaving an edited document.
- TypeScript and ESLint passed. First full frontend run found expected old-copy/
  breadcrumb assertions plus a timing issue in an API-backed auth test: it clicked
  Save while role details were still loading. Added a wait for the existing enabled
  state before asserting the PATCH request; did not change auth behavior.
- Rendered first pass checked directory and editor at 1440px and 390px. Directory
  controls occupy one desktop row; mobile preserves order and wraps breadcrumbs.

## Review and final checks

- Checked call-spec lists, tenant services, role creation, API-key creation and
  long-label call history in headless Chrome. Mobile call history wraps the trail
  without horizontal overflow; API-key form actions remain below the fields.
- Checked the service directory and Google AI Studio modal in light theme, then
  dismissed the modal and followed Services back to the connected inventory.
  Existing capability tags and modal focus return remain intact.
- Updated DESIGN.md to record the user-approved breadcrumb hierarchy and desktop
  directory control order. Existing sidebar tenant navigation and modal Back
  controls are intentionally retained. No design suppressions were added.
- Legacy standalone onboarding tests now reach the tenant directory through the
  existing global navigation instead of a removed page breadcrumb. The new API
  key navigation test waits for the async form before clicking its ancestor.
- Full frontend suite passed: 844 tests across 108 files. TypeScript, ESLint and
  the static Storybook build passed. All required umbrella
  gates passed: format, compile with warnings as errors, strict Credo, tests and
  unused-dependency check. No Lean lane was required for this presentation change.
- Worktree inspection preserved preceding service-design work and unrelated MCP
  planning files. No files were staged or committed. Storybook remains on 6006.
