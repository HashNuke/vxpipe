# Unified integrations page

## Scope and decisions

- Storybook design only. Preserve the live API navigation projection and existing
  route contracts; no credential, OAuth or backend implementation in this change.
- Merge connected inventory and the directory under tenant Integrations and
  Platform Integrations. The latest user correction makes Connected integrations
  the default in both scopes.
- Category links have distinct hash URLs in the preview and are reflected in the
  breadcrumb. Desktop anchors and the mobile dropdown share routing. Ancestor and
  main sidebar links return to Connected integrations; direct loading, reload and
  browser history preserve categories.
- Connected rows share the directory presentation, grouped into AI services,
  Telephony and tenant-only MCPs. Platform pages expose only connected, AI and
  telephony categories; no custom MCP action or inherited third-party MCPs.
- Tenant-owned connections retain the Already connected notice. Connecting an
  inherited provider opens tenant credentials so a tenant override can be saved.
- Existing pending, validation, unavailable, removal and read-only fixtures remain
  available through shared preview adapters. The live provider card keeps its
  default presentation; row layout is opt-in for the prototype.

## Implementation and review checkpoints

- Wrote focused failing tests for the merged layout, platform exclusion and tenant
  overrides before implementing the shared inventory. Added failing URL/default/
  breadcrumb tests before category routing. A final failing test exposed main
  sidebar navigation retaining AI models; preview navigation now notifies the
  category route and resolves the base page to Connected integrations.
- Updated existing story tests to use category navigation rather than the removed
  Connect a service picker. Reset browser location between routed preview tests.
- Initially renamed labels in the shared navigation policy. Full frontend tests
  exposed a live projection/parser dependency on those strings. Reverted that
  change and kept the display rename opt-in in the Storybook shell. Production
  App/navigation regression checks passed (43 tests).
- Reviewed the merged layout with the Impeccable workflow and headless Chrome via
  agent-browser. Desktop 1440px dark tenant and light platform views preserve
  hierarchy and row actions. At 390px the header stacks and categories use a
  dropdown without horizontal overflow. Platform review confirms no MCP controls.
- Confirmed actual browser Back/Forward, reload, AI category URLs, the mobile
  Calendar route, and tenant/platform breadcrumb labels. Previously reviewed
  connected mobile inventory includes the MCP group and management actions.
- No design suppressions added. No global typography or unrelated styling changes.
  Existing worktree changes from earlier requests were preserved; no commit made.

## Verification evidence

- Focused preview/navigation tests: 86 passed. Full frontend suite: 109 files,
  852 tests passed.
- TypeScript check, ESLint and static Storybook build passed. Build retains its
  existing large-chunk warning. Browser sessions were closed; the existing
  Storybook development server on port 6006 was left running.
- Umbrella format check, compile with warnings-as-errors and strict Credo passed.
  The full umbrella test run had one timing failure in the unchanged speech-output
  deadline test: the expected message arrived at the 100ms assertion deadline.
  Its focused rerun passed (1 test). All other umbrella applications passed.
  No backend change was made for this isolated timeout.
- Unused dependency check and git diff whitespace check passed.

## Follow-up boundary

Production category routes, authoritative connection lookup and persistence are
still future implementation work after review. The Storybook directory uses local
fixtures; a refresh resets credentials and connections while retaining the URL's
category.
