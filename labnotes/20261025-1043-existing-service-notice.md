# Existing service notice

## Scope and decisions

- Storybook-only continuation of the tenant integrations design. No database,
  OAuth, credential storage or production route changes.
- Directory entries remain independent of connection state. On Connect, the
  preview checks the tenant's current simulated records and shows an Already
  connected modal with the service and tenant names, Close and View services.
- Both AI/telephony and MCP connections use the notice. Inherited providers name
  the platform source; records needing repair say Already configured. Existing
  inventory management actions still open their management dialogs directly.
- Adapters supply the same provider records their inventories display, including
  newly saved connections, instead of using a separate default fixture list.
- The real backend must look up the complete tenant inventory on selection and
  enforce uniqueness on save; partial/paginated inventory is not sufficient.
- User steering renamed the title and breadcrumb to Integrations directory.
  The existing Storybook route is retained for bookmarks.
- Further steering removed capability tags from both Storybook credential-modal
  implementations. Directory listings retain their tags.

## Evidence and verification

- Five focused cases failed first: existing MCP, existing telephony, a newly
  saved provider, the navigation inventory and the legacy inventory. They then
  passed after the shared pre-credentials notice and inventory adapters landed.
- Updated the old Deepgram credential case to an unconnected provider and added
  coverage of the inherited Deepgram notice. Focused suite: 22 tests passed.
- Full frontend suite: 847 tests across 108 files passed. Removed a redundant
  testing-library option flagged by TypeScript; exact string names already match.
- Reviewed the compact notice in headless Chrome at 1440x1000 and 390x844, in dark
  and light themes. No overflow or unnecessary form space. Closing restores the
  directory query and trigger focus; View services returns to the inventory.
- Initial static build command used the assets directory, which has no Storybook
  configuration. Corrected it to run from the umbrella root.
- Confirmed both credential-modal implementations without capability tags at
  desktop and mobile sizes (Google AI Studio and the original Choose services
  Deepgram flow). Directory tags remain visible; labels and footer actions fit.
- The post-removal focused run found two older onboarding assertions requiring
  modal tags. Updated them to assert directory capabilities and absence from the
  form. The final full frontend suite passed all 847 tests in 108 files.

## Completion checks

- TypeScript, ESLint and the corrected static Storybook build passed.
- All required umbrella checks passed: format, compile with warnings as errors,
  strict Credo, the full test suite and unused-dependency check. No state-machine
  changes were made, so the Lean lane was not applicable.
- Preserve preceding worktree changes. No staging or commits requested.
