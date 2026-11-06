# MCP service connection design preview

Status: Storybook-only workflow for review, 2026-10-25. No backend, production
route, credential persistence, OAuth callback, or live MCP connection is added.
The components live under `assets/src/admin/mcpStories` in `vxpipe_console` and
are imported only by Storybook previews and their focused tests.

## Review entry points

- [Tenant Integrations](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--tenant-services)
- [Existing Choose services story](http://localhost:6006/?path=/story/vxpipe-console-services-tenant-services--choose-services)
- [Platform Integrations](http://localhost:6006/?path=/story/vxpipe-console-services-platform-services--platform-services)
- [AI models category](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--service-directory)
- [Conflict notice: AI service](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--already-connected-ai)
- [Conflict notice: MCP](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--already-connected-mcp)
- [Google AI Studio credentials](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--connect-google-ai-studio)
- [Deepgram credentials](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--connect-deepgram)
- [Telnyx credentials](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--connect-telnyx)
- [Remote categories](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--remote-categories)
- [Paginated directory](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--paginated-directory)
- [Version-filtered global search](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--version-filtered-search)
- [Loading next page](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--loading-directory-page)
- [Page retry](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--directory-page-error)
- [Directory outage](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--directory-unavailable)
- [Cached directory](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--cached-directory)
- [Connection-status failure](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--connection-status-unavailable)
- [Custom MCP](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--custom-mcp)
- [Manual OAuth](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--custom-o-auth)
- [CIMD](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--manual-cimd)
- [DCR](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--manual-dcr)

The same Storybook group includes each preset, static credential variants,
anonymous access, checking, simulated authorization, error, reconnect, empty,
read-only, light-theme and mobile states. Use sample credentials only. Refreshing
a story resets its in-memory state. Tool catalogs and connected accounts are
illustrative, not live discovery results.

## Decisions represented by the prototype

Tenant **Integrations** combines the connected inventory and service directory in
one layout. **Platform Integrations** uses the same layout for installation-wide
AI and telephony connections. Both open **Connected integrations** by default.
The category sidebar starts with Connected integrations, a separator, AI models
and Telephony. Tenants also have a separator followed by Calendar, CRM and Office
suite. Mobile uses a category dropdown with the same navigation behavior.

Connected integrations uses the directory's flat rows, grouped into **AI services**,
**Telephony** and, for tenants only, **MCPs**. Connected indicators use the same double checkmark without a visible status label.
Inherited-source labels are omitted throughout native and remote listings. Inherited
management requires `platform_services.write`; tenant-owned integrations remain
manageable with tenant write permission. Platform pages never show
MCP inventory, MCP categories or Connect other MCP. Third-party MCP connections
are tenant-owned and never inherited.

Every category is a distinct preview URL: `#/t/<tenant-key>/services/<category>`
or `#/platform/services/<category>`. Categories are `connected`, `ai`, `telephony`,
`calendar`, `crm` and `office`; platform category browsing allows only the first three.
Direct links, reloads and browser Back/Forward preserve the category. Existing
Storybook IDs and production base routes remain unchanged. These hash routes are
preview navigation, not newly implemented backend endpoints.

Search is global: entering text opens `/services/search?q=...`, regardless of the
previous category, and searches MCP, AI and telephony entries. Platform search
retains its AI/telephony-only scope. Choosing a category exits search. Remote
results use Previous/Next controls and server-owned ranges, totals and opaque
cursors; the cursor is also retained in the URL. Search covers unloaded pages,
and query/category changes reset pagination. Pending or failed page requests keep
the current rows visible, with a retry action when needed. Expired links offer a
restart from the first page. These are fixture-driven states, not real requests.

Each simulated request includes `X-VxPipe-Version`, read from the root `VERSION`
file at build time. The simulated server excludes entries unsupported by that
version before counting or paging. Search for Google to see AI Studio alongside
Calendar, Sheets and Docs; search for Example in Version-filtered global search
to see the supported MCP without the future AI adapter. Native results reuse the
installed provider definition, credential form and local connection status.

Breadcrumbs read `Tenant > Integrations > Category` or
`Settings > Platform Integrations > Category`. The Integrations ancestor and main
sidebar entry return to Connected integrations. Category links are real anchors;
modifier-clicking can open their URLs separately. Explicit directory and modal
stories may start in the relevant category to demonstrate that state.

Directory entries resolve connection state before offering an action. Unconnected
entries offer Connect; connected entries offer Edit and a double checkmark.
Inherited AI/telephony providers show their source and offer a tenant override
inside the editor. Expired/invalid connections show an attention state, not a
connected marker. Closing the editor preserves the directory filter and focus.
The older Already connected stories remain conflict-recovery previews; they are
no longer the ordinary directory selection flow.

Local AI/telephony definitions and effective connection records remain separate
from the simulated hosted catalog. It contains MCP templates and native provider
references for global search, with no downloadable adapters. Remote categories and entries are data,
including their names, optional logos, setup metadata, endpoints and auth recipes.
The expanded-directory story adds a Knowledge base category entirely through a
fixture response. Catalog outages preserve local categories and saved MCP
management. Stale listings allow editing but block new remote connections until
refresh succeeds. Status loading/failure never presents unknown records as
unconnected. The loading story resolves after a simulated 1.2-second fetch; skeletons
appear for pending remote content, while local inventory and built-in categories
remain immediate. The prototype is local state only, with no outbound API requests.

See the [remote API handoff](integrations-directory-api.md),
[JSON Schema](integrations-directory.schema.json) and
[example response](integrations-directory.example.json) for the separate directory
project and the proposed future Vxpipe status-projection boundary. The hosted
catalog must never receive tenant credentials or enabled-state information.

Capabilities appear as individual outlined tags in directory and connected
provider rows, wrapping on narrow screens. Credential dialogs do not repeat them.
The desktop header places title, search and Connect other MCP in that order;
mobile stacks them. The custom MCP action is tenant-only.

Existing Tenant services, Platform services, Tenant inventory, navigation journeys
and Morse API stories use this workflow too. Error, pending, saved-credential,
tenant override and read-only scenarios remain available. The shared provider
card has an opt-in row layout for these previews; live pages retain their existing
card presentation and navigation contract. Directory backend behavior is not
implemented; the shared build-version source also feeds the umbrella OTP applications.

Each Connect action opens a credentials modal for that specific service. There
is no service dropdown or in-modal catalog navigation. Cancel, close and Escape
preserve the directory query/category and restore focus to the selected service.
Successful simulated connection returns to the connected inventory. Presets fill
the remote endpoint; custom MCP connections retain its full URL and path.
Desktop forms align labels and controls in rows; mobile forms stack them. Every
credential modal owns a padded, scrollable body and a separate footer.

AI/telephony credential dialogs show the service name, fields
and actions, without provider descriptions or tenant/preview disclaimers.
Simulation details belong to Storybook documentation. The dialogs are local to
the prototype. The previous
composition removed shared dialog padding without adding a body wrapper, which
left the legacy credential form flush to the edges. The new dialog fixes that
composition without changing shared production components. Test/save operations
remain simulated; provider validation reuses the existing pure validator.

Custom servers begin with no selected authentication method. URL-triggered
discovery prefills the method where possible; users can also select CIMD, DCR,
or a custom authentication method directly. CIMD and DCR are displayed as
OAuth registration choices, not as substitutes for consent. Anonymous access is
an explicit choice, never an error fallback.

| Choice | Reviewable configuration |
| --- | --- |
| CIMD | App-managed discovery, metadata, callbacks and request parameters; no extra fields |
| DCR | App-managed discovery and registration; optional initial registration token for protected registration |
| Bearer token | Masked token and optional additional MCP headers |
| Custom headers | Editable header names and masked values |
| HTTP Basic | Username, masked password and optional additional headers |
| OAuth - Own client | Client ID, secret or signing key, token endpoint authentication, authorization-code/PKCE or client-credentials grant |
| No authentication | Endpoint only |

OAuth - Own client advanced settings include issuer, explicit authorization/token/revocation
endpoints, scopes, resource, audience, extra authorization/token request values
and additional MCP request headers. Callback, state and PKCE are application-owned
values. The prototype rejects conflicting standard parameters and malformed
headers, but is not a backend validation or interoperability implementation.

Management previews search, tool refresh, reconnect and disconnect. Catalog
refresh does not enable new tools for an agent. Agent selection and explicit
tool-name allowlists remain in the existing call spec editor; this prototype
does not change that UI or its runtime.

## Verified preset information

Documentation was checked on 2026-10-25. These are setup templates, not claims of
completed Vxpipe provider integration.

| Preset | Endpoint | Setup shown |
| --- | --- | --- |
| Cal.com | `https://mcp.cal.com/mcp` | Automatic OAuth with CIMD/DCR |
| Google Calendar | `https://calendarmcp.googleapis.com/mcp/v1` | Own Google Cloud OAuth client; Developer Preview |
| Google Sheets | `https://sheetsmcp.googleapis.com/mcp/v1` | Own Google Cloud OAuth client; Developer Preview |
| Google Docs | `https://docsmcp.googleapis.com/mcp/v1` | Own Google Cloud OAuth client; Developer Preview |
| HubSpot | `https://mcp.hubspot.com` | Own MCP connector OAuth client |
| Calendly | `https://mcp.calendly.com` | OAuth with DCR |

Google documents Calendar, Sheets and Docs as separate MCP endpoints, all in
Developer Preview, in its [supported-products list](https://docs.cloud.google.com/mcp/supported-products).
Their setup guides cover required Cloud project and OAuth client setup:
[Calendar](https://developers.google.com/workspace/calendar/api/guides/configure-mcp-server),
[Sheets](https://developers.google.com/workspace/sheets/api/guides/configure-mcp-server),
[Docs](https://developers.google.com/workspace/docs/api/guides/configure-mcp-server).

Other provider references:
[Cal.com](https://cal.com/docs/mcp-server),
[Calendly](https://developer.calendly.com/docs/mcp/calendly-mcp-server),
[HubSpot](https://developers.hubspot.com/docs/apps/developer-platform/build-apps/integrate-with-the-remote-hubspot-mcp-server).
The protocol reference is the approved
[MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

## Verification boundary

Focused interaction tests cover catalog/custom search, category controls,
fixed-provider credentials, cancellation/focus return, full endpoint retention,
no network calls during simulated connection, OAuth configuration, masked
credentials, cancellation and tenant-local reconnect/disconnect behavior.
Rendered inspection covers 1440×1000 desktop, 1024×768 intermediate and 390×844
mobile layouts, dark and light themes, advanced forms and important connection states. Checkpoint test
results and review findings are recorded in the associated labnotes.

Backend implementation still requires durable tenant isolation, encrypted
credential/grant storage, discovery and registration, callback validation, token
refresh, live MCP initialization/catalog loading, call-runtime wiring and provider
interoperability checks. See the [integration proposal](../tenant-mcp-integrations.md).

## API consumption and unlisted-server proposal (2026-10-25)

The [new milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md)
splits delivery into T0–T8. The [research and decisions](integrations-directory-consumption.md)
define API-first browsing, installed-provider fallback and the remaining outbound
MCP backend work. These screens remain local simulations, with no credentials
sent or saved. API request fixtures now use the deployed `category` parameter and
accept omitted minimum-version bounds.

Review these stories on port 6006:

| Story | What to exercise |
| --- | --- |
| [AI models](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--ai-models) | Returned directory page uses the existing native credential form |
| [Directory unavailable](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--directory-unavailable) | Installed AI/telephony rows appear immediately; search Google, then retry to restore all results without losing the query |
| [Custom MCP](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--custom-mcp) | Enter a URL to discover editable authentication settings; server identity is supplied at connection time |
| [Registration required](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--registration-required) | Copy callback for manual registration and enter client details; MCP identity/URL are preserved |
| [Discovery failed](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--discovery-failed) | Inline discovery failure with retry and manual setup; failure never silently becomes anonymous access |
| [Installation URL required](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--installation-url-required) | OAuth cannot continue; static bearer/anonymous configuration remains usable |
| [Discover no authentication](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--discover-no-authentication) | URL discovery selects No authentication before Connect, without prompting for sign-in |
| [Connected without tools](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--connected-without-tools) | Successful connection with no usable tools has an explicit outcome |

Existing Manual CIMD, Manual DCR, Custom OAuth, Bearer Token, API Key And Headers,
Basic Auth, No Authentication, pagination, unknown connection status, reconnect,
read-only and platform-integration stories remain part of the proposal. JWT and
client-credentials controls represent the advanced-authentication task, not shipped
backend support. The existing Cached Directory variant is an alternative retained
for discussion; this milestone chooses local fallback after a failed refresh.

The build preserves the incumbent Console design. Desktop 1440×1000 and mobile
390×844 inspection covers recovery dialogs, the retained-draft form, outage rows,
limited search and successful retry, including a light-theme failure state. Tests
exercise behavior rather than screenshots. Detailed evidence belongs in the
[checkpoint labnotes](../../labnotes/20261025-1834-integrations-directory-proposal.md).

## Simplified MCP connection forms (2026-10-25 user review)

- No MCP form asks for a connection name. Directory entries use their service name;
  custom connections use server metadata (the Office tools metadata fixture here).
- Directory MCPs do not expose endpoint/authentication/grant selectors or advanced
  configuration. OAuth presets need only authorization; registered-client presets
  show the required client credentials. Static-auth templates show their secrets.
- Custom MCPs retain URL and authentication configuration. CIMD/DCR callbacks and
  client-metadata URLs are managed internally and have no fields in either path.
- Callback copy controls remain only where manual OAuth client registration needs
  the user to register that URL. Google Calendar/HubSpot illustrate that exception.
- Connected fixtures now use Cal.com and HubSpot rather than connection aliases;
  their editors also keep directory-owned configuration hidden.

Review Calendly/Cal.com for the compact authorization form, Google Calendar for
registered-client credentials, and Custom MCP/Manual DCR for the custom path.

The outage notice sits below sidebar categories (below the mobile category selector).
Its copy is exactly “Integration directory unavailable” followed by “Showing built-in
AI and telephony services”; a labeled retry icon retains recovery without more prose.

## MCP management review updates

Manage opens left-aligned Authentication and Tools tabs in one stable-height dialog.
The title and close control share the first row; account/workspace appears below it; the adjacent info tooltip identifies the auth mechanism.
Reconnect and editable credentials are available immediately in Authentication.
Reconnect and Save changes sit inside that tab; Disconnect and Close remain in
the same modal footer across both tabs. Tools has a heading-aligned refresh control
(icon only on mobile), search and its own scroll area. Refresh disables the button
and spins its icon during the simulated request, then restores the button without
adding a success message. Reduced-motion users retain the disabled/busy state
without spinning. Redundant tenant scope, preview-data and tool-allowance notices
are omitted. Existing agent tool selections remain unchanged by refreshing.

The [tenant integration manager preview](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--tenant-integration-manager)
demonstrates blocked inherited management without platform write permission. The
[loading preview](http://localhost:6006/?path=/story/vxpipe-console-services-mcp-integrations--directory-loading)
resolves automatically and preserves the category selected during loading.

## Optional MCP setup information

Definitions may supply independent `setup_notes`, `setup_url`, and
`documentation_url` fields. Connect dialogs and the Authentication tab show the
plain-text notes above a row of Setup and Documentation links. Missing values
create no empty rows. HubSpot demonstrates notes plus Documentation; the Example
knowledge MCP in Remote categories demonstrates both links. Callback URLs remain
read-only and copyable, with a muted surface that distinguishes them from inputs.

## Single authentication selector (2026-10-31 user review)

Custom MCPs expose all methods directly in the Authentication dropdown:
OAuth - CIMD, OAuth - DCR, OAuth - Own client,
Bearer token, Custom headers, HTTP Basic, and No authentication.
There is no Custom authentication option or nested Authentication type selector.
Selecting a method shows its fields immediately; saved connections reopen with
that method selected. OAuth - Own client retains the callback copy control for
manual registration. CIMD/DCR metadata and callbacks remain app-managed.

The Authentication selector shows method-specific fields without explanatory
paragraphs beneath it. Custom headers supports one or more editable name/value
pairs with Add header and Remove header controls.

The single custom MCP method selector is labeled **Authentication Type**.
The surrounding Authentication section and saved-connection tab keep their names.

## URL-triggered discovery (2026-11-06 user review)

Connect other MCP starts a local discovery simulation when a complete HTTPS URL
is entered or changed. After a 350 ms debounce it shows Checking MCP server,
then Discovering OAuth settings, then an editable result. The default fixture
selects OAuth - CIMD and fills issuer, authorization/token/revocation URLs, scopes,
and resource. These values are illustrative, not inferred facts about the URL;
the prototype makes no discovery HTTP requests. Server identity still comes from
the simulated connection/initialize outcome, not OAuth resource metadata.

Authentication Type begins with a disabled Select authentication type placeholder.
Discover automatically is no longer a method. The Endpoint configuration selector
is removed; OAuth endpoint fields are directly editable within OAuth endpoints and
scopes. Entered OAuth URLs are validated as HTTPS without a mode switch.

URL changes clear the previous server's settings and credentials, cancel pending
results, and start again. Manual edits made during discovery take precedence over
prefills. Closing the modal cancels discovery. Connect remains disabled until a
method is discovered or selected explicitly. Discovery failed presents an inline
message, Retry discovery, and manual setup; it never defaults to anonymous access.
Discover no authentication demonstrates an anonymous result before Connect.

Review Custom MCP by entering any complete HTTPS URL, then changing it; use
Discovery failed and Discover no authentication for the alternative outcomes.
The existing manual-authentication stories retain their initial method so they
remain useful field previews; editing their URL starts discovery as usual.

Custom headers shows its name/value editor directly and omits the empty Additional
parameters section. Other authentication methods retain their applicable parameters.

## CIMD and DCR field review (2026-11-06)

For these two authentication types, hide OAuth endpoints and scopes, audience,
resource overrides, authorization/token parameter editors, and additional MCP
headers. DCR also hides the registration URL and arbitrary registration parameters.
Discovery and the client implementation own these values; changing to CIMD/DCR
must not validate hidden manual overrides left over from another method.
OAuth - Own client retains its manual configuration, including discovered defaults.

CIMD requires no additional input in this modal. DCR retains only the optional
Initial registration token, masked, because protected registration can require a
user-supplied initial access token. Open registration does not require one.
This is a UI decision, not a claim that extension parameters are forbidden.

Sources reviewed: [MCP authorization, discovery and client registration](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
and [RFC 7591 §3, initial access tokens](https://www.rfc-editor.org/rfc/rfc7591.html#section-3).
The alternative of keeping generic override editors was rejected for these managed
flows: it implies ordinary setup requires users to supply protocol-owned values.

Changing Authentication Type clears the previous method’s header rows, including
secret values. Custom headers starts with an empty X-API-Key row; Bearer, HTTP
Basic and Own client start with no additional headers. Switching through CIMD,
DCR or No authentication cannot carry header credentials into a later selection.

Saved custom connections use the same URL-triggered discovery when their URL is
edited in Manage. Save changes stays disabled until authentication is selected or
discovered, and progress/retry remains visible there. Switching an Own-client
draft to client credentials ignores an unused authorization-code endpoint.
