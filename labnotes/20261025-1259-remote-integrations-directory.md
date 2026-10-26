# Remote integrations directory

## Scope and decisions

- The user requested updated tenant Storybooks and a remote API plan for a separate
  project. Implemented only local preview data/state and documentation. No remote
  API requests, backend routes, database migrations or real OAuth work were added.
- Keep Connected integrations, AI models and Telephony local. MCP category IDs,
  labels and entries come from a simulated hosted catalog; Platform Integrations
  still excludes MCP categories entirely. Both scopes default to connected rows.
- Resolve local saved state before rendering directory actions: Connect when
  absent, Edit plus a double checkmark when connected, Edit plus attention when
  authorization needs repair. Inherited providers retain an override flow.
- Match directory connections by permanent directory namespace and entry ID,
  never by endpoint/name. Save connection configuration independently of catalog
  refresh. Existing explicit conflict-notice stories remain recovery examples.
- Chose a bounded, atomic public `/v1/catalog` snapshot for the separate project,
  with schema/revision/ETag, category and entry metadata, fixed Streamable HTTP
  endpoints, and declarative OAuth/static/anonymous authentication recipes.
  No executable plugin code or tenant enabled-state data belongs in that API.
- The handoff documents a separate future local status-projection boundary,
  tenant isolation, duplicate-save races, retention of saved config, offline
  behavior, schema compatibility and publication acceptance gates. Its checklist
  is explicitly future work, not an implemented backend milestone.

## Implementation checkpoints

- Focused tests failed first on absent saved-state actions and data-driven
  categories. Added the remote fixture/type adapter, reusable row actions,
  category routing without a hardcoded MCP enum, and saved-connection editing.
- Added loading, unavailable, cached-directory, unknown connection-status and
  reconnect-needed stories. Remote outages retain local categories and management;
  stale catalogs disable new remote connections but retain Edit. Connection status
  failures offer Retry without guessing that a record is absent.
- Existing preview tests exposed a legacy inventory adapter that only initialized
  its editor from the connected view. Fixed it to use the selected provider and
  editing intent from either view, preserving existing saved credentials.
- A focused failing test also exposed unavailable local inventory being treated
  as an empty list. Propagated load status through tenant/onboarding adapters;
  incomplete inventories no longer advertise Connect in the directory.
- Ordinary connected selection no longer uses the old Already connected notice.
  Updated tests and current design documentation to reflect the user's new request.

## API evidence and validation

- Checked the approved MCP 2025-11-25 authorization and transport documentation.
  CIMD/DCR are OAuth client-registration choices; server metadata discovery still
  owns actual capabilities. Directory auth data supplies setup hints only.
- Added `docs/development/integrations-directory-api.md`, a draft-07 JSON Schema,
  and a fictional example response. The separate project can implement these
  without importing UI components.
- Validated the schema/example with the repository's existing Ajv installation,
  including OAuth CIMD/DCR/preregistration, bearer, Basic, API-key and anonymous
  variants. Confirmed rejection of reserved category IDs, unknown auth types and
  endpoint query strings. Cross-record identity/reference checks remain specified
  publisher/consumer obligations rather than claims made about JSON Schema alone.
- No dependencies were installed. The initial Python validator probe found no
  jsonschema module; used existing Ajv instead. Initial test-file shell writes used
  an incorrect relative working directory and made no changes; corrected the path.

## Verification

- Focused suite: 67 tests passed. Full frontend suite: 110 files, 860 tests passed.
- TypeScript, ESLint and static Storybook build passed. Existing bundle-size
  notices remain informational.
- All required umbrella checks passed: format, compile with warnings-as-errors,
  strict Credo, full tests and unused dependencies. No Lean lane is required for
  these UI/documentation changes.
- Used Impeccable's existing design context and hardening guidance. Inspected
  headless Chrome at 1440px and 390px: mixed Connect/Edit rows, connected markers,
  inherited state, new remote category, directory outage, saved catalog and
  connection-status error. Confirmed mobile category URL navigation and successful
  Retry directory behavior. Dark and light surfaces preserve the existing system.
- No design suppressions or global typography changes. Closed this task's browser
  session and left Storybook running on port 6006. No commit made; earlier user
  worktree edits remain intact.
