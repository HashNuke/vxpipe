# Production Integrations interface

Status: native integration management and custom-MCP forms are implemented,
including [OAuth fields and nonsecret callback recovery](mcp-oauth-ui.md).
Listed-MCP recipes, retained-ID recovery and authenticated MCP/outage flows pass
[rendered acceptance](mcp-browser-acceptance.md). Final verification, external release and user approval remain in the
[integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
This checkpoint follows the [directory contract](integrations-directory-consumption.md).

## Reusing Services

Integrations replaces the Services presentation at `/platform/services` and
`/t/:tenant/services`; category paths extend those routes. Existing native
credential validation, save, removal, override and restore APIs remain authoritative.
The combined inventory and category endpoints only compose browsing data with
local status. They do not implement another native credential store or lifecycle.

Opening a native action loads the existing Services settings and invokes the
existing credential dialog and handler. Browsing does not eagerly load all model
settings. Native rows use bundled provider logos and capability metadata from the
installed registry, including for readers and directory outages. Public listings
cannot invent executable native capabilities. Telephony retains its existing
application controls and settings request.

Native credential writes use `tenant_api_keys.write` or installation-scoped
`platform_services.write`. MCP writes use `tenant_services.write`. The frontend
keeps these separate and the backend rechecks each operation. Tenant inherited
rows permit an override only when tenant credential writes are allowed. A
platform-only writer manages the shared binding from Platform Integrations.
Named credential removal uses the exact binding ID; restoring a tenant override
never deletes the platform credential.

## Browsing and recovery

Connected inventory is local. Browse/search uses the hosted directory, joined
with authorized local status. Unknown local status blocks mutation controls.
Remote failure offers installed native entries with a sidebar notice, preserving
query/category navigation. The server cache contains only public data.

Category and search changes cancel obsolete reads. Pagination keeps the previous
page while loading the next cursor and retains those rows if that request fails.
Invalid or expired cursors offer a first-page restart preserving query/category.
The production wrapper keeps the inventory component mounted across navigation;
an inline component type would lose this retained state.

The tenant custom-MCP action remains available on empty and outage pages when
local status and write permission are known. Platform pages have no MCP controls.
Remote logo failures use a neutral icon; native logos remain local assets.

## Static custom MCPs

A URL edit debounces one authenticated backend discovery operation, which may
perform multiple bounded protocol reads. Results are bound to tenant, endpoint,
issuer and draft revision. A changed URL clears old credentials and ignores stale
results; explicit authentication choices take precedence over late discovery.
There is no Discover automatically authentication or endpoint mode.

Bearer, Basic, named custom headers and no-authentication forms send only active
credentials. Switching methods clears old header names and secret values; only
Custom headers starts with an empty X-API-Key row. Saved credentials are never
loaded into inputs. Replacement is explicit, and stale-generation failures retain
the dialog with recovery instructions.

Management exposes Authentication and Tools tabs. Refresh tools sends only
`generation` and `refresh_tools: true`, preserving saved configuration and ignoring
unsaved credential edits. Successful configuration saves retain the effective
selected method, including a discovered anonymous endpoint. Disconnect and create
refresh the local inventory. Read-only viewers can inspect tools without mutation
controls. Unsupported OAuth discovery remains explicit and blocks OAuth submission.

Saved management uses an anchored, viewport-capped frame so switching tabs keeps
the header and footer stable. Authentication content and the tool list scroll
within that frame. Backdrop dismissal requires a primary pointer gesture that
begins and ends on the backdrop. Gestures beginning or ending inside the dialog,
cancelled gestures, and gestures observed while busy at press, release or click
must not discard the dialog. Explicit Close and Escape remain available
when idle. This behavior is covered by focused gesture regressions and authenticated
desktop/mobile Chrome checks; see the
[dialog evidence](../../labnotes/20261107-1229-stabilize-mcp-dialog.md).

## Alternatives and evidence

Rejected: a second native credential implementation, eager Services/model reads
for every browse, one shared native/MCP edit flag, deriving native capabilities
from remote labels, remounting the inventory on every location change, and using
configuration replacement to refresh tools.

Production-wrapper regressions cover granular roles, native override/restore and
exact named removal, retained pagination, anonymous save and catalog-only refresh.
Directory/API tests cover private inventory, local fallback, status joins and
category navigation. Initial desktop/mobile Chrome inspection used the production
components with in-memory responses. It establishes layout and fixture interaction,
not authenticated backend/browser acceptance. Checkpoint evidence and limitations
are recorded in [labnotes](../../labnotes/20261107-0309-review-integrations-ui.md).
Later [authenticated acceptance](mcp-browser-acceptance.md) records actual Console
and controlled HTTP/TLS peer checks, with the remaining milestone gates explicit.
