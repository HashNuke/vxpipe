# Compact console navigation

## Scope and decision

- Implement the user-approved two-row tenant workspace: brand, tenant breadcrumb
  and account actions above sibling navigation and page actions.
- Remove the inert Admin navigation item, terminal page breadcrumb, and visible
  duplicate page heading. Keep an accessible heading and existing routes.
- Apply consistently to Services, Call definitions and Calls. Call details already
  uses a compact console header and local return link.
- Preserve the existing uncommitted provider-logo, credential, fixture, dependency
  and onboarding-labnote changes. No commits requested.
- Desktop service inventory previously starts at 281px; mobile at 265px.

## Verification

- Added focused page-boundary checks before implementation for header context,
  active navigation, accessible headings, tenant return links and modal isolation.
- Red: all four focused checks failed for the expected reasons: no tenant
  breadcrumb in the app header, and account actions remained interactive while
  credential setup was open. The first test run exposed an ambiguous jsdom
  header-role query; scoped it to the brand's header before confirming the red.
- Green: all 59 tests across workspace layout, the three tenant pages, the full
  Storybook journey and production AdminApp passed. TypeScript and warning-free
  ESLint checks passed.
- First rendered pass: Services inventory starts at 114px on 1280px desktop and
  162px on 390px mobile, reclaiming 167px and 103px respectively. The action shares
  the desktop navigation row and moves below it on mobile.
- Header breadcrumbs preserve real links and injected navigation. The breadcrumb
  describes tenant location; the workspace link owns current-page semantics.
- Credential setup now makes the relocated header inert and hides it from the
  accessibility tree, restoring access on dismissal alongside trigger focus.
- Complete frontend suite: 120 tests passed across 22 files; TypeScript,
  warning-free ESLint, CSS generation and the Storybook production build passed.
  Storybook retained its existing large-bundle advisory. Generated preview output
  was moved outside the worktree into temporary storage.
- Bounded Chrome inspection covered dark desktop/mobile Services, long tenant
  names, empty and unavailable inventory, light desktop definitions, mobile Calls,
  and the credential dialog. The full journey preserved Services → Calls →
  definitions → Tenants navigation. Escape restored Add credential focus and
  header access. No page-level horizontal overflow was observed.
- A 320px layout probe inserted the production Sign out button classes into the
  isolated Storybook header: the account action and all three destinations stayed
  within the viewport, while the long tenant name truncated locally. This was a
  layout probe, not a real authenticated sign-out test.
- Other work continued modifying service inventory and editing behavior during
  this task. Those changes were preserved; after the shared Services page changed,
  the 16 layout/services/journey tests passed again. Inventory column clipping in
  the narrow preview belongs to those in-progress inventory changes, not this
  navigation checkpoint.
- The design hook requested a companion metadata refresh after DESIGN.md changed.
  Clarified the existing segmented-tab example as call-workbench navigation and
  recorded the separate tenant-navigation pattern; visual tokens are unchanged.
- Root formatting, warnings-as-errors compilation, strict Credo and unused-lock
  checks passed. The complete umbrella test run (seed 227049) reported one Gateway
  failure: 438 gateway tests, 1 failure, 7 exclusions. Console's 156 backend tests
  passed. No Gateway implementation was changed for this navigation work.
- `mix test --failed` isolated the failed Gateway test and passed: 1 test,
  0 failures (seed 625337). The original full-suite failure remains recorded;
  the focused rerun does not establish its cause or make the initial run green.
- Final diff whitespace check and companion design metadata JSON validation passed.
  No changes were committed.
