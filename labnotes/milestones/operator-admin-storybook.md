# Operator admin Storybook

Status: complete; all 7 checkpoints are implemented and the user approved the reviewed UI for
production integration on 2026-09-17. Requested and independently reviewed 2026-09-17.
Prerequisites: the private React package and completed component/model slices of the in-progress
[Call debug console](call-debug-console.md).
Sources: [Developer console design](developer-console-and-onboarding.md),
[React styling contract](../../docs/development/react-component-styling.md), and
[Call-details model](../../docs/debug-console-call-details-model.md).

## Runnable outcome

The existing debug-console Storybook presents the complete operator administration experience with
deterministic mock data. A reviewer can move from the tenant list into one tenant workspace, browse
that tenant's call specs, optionally filter its calls by a call spec, inspect an ongoing or ended
call, and configure the tenant's supported AI and telephony services.

Every page intended for the first `/admin` application is visually and interactively reviewable
before authentication, database queries, JSON endpoints or production admin routes are implemented.
The Phoenix-rendered login/auth pages are the only UI excluded from this Storybook milestone.

## Contracts

- This milestone implements React components, stories, fixtures and focused frontend tests only.
  It does not add or change Phoenix routes, controllers, LiveViews, sessions, persistence schemas,
  Calls workflows, repositories or production endpoint clients.
- Admin-specific components live under Console assets. Reusable call state remains in
  `@vxpipe/core`; reusable call UI remains in `@vxpipe/react`. Do not move tenant administration
  concepts into the reusable packages.
- Console owns the admin stories inside the existing `@vxpipe/react` Storybook. Those stories
  consume the same component exports the production React application will later use. The
  production app must not receive a second implementation or a second Storybook server.
- Use shadcn's source-owned component composition and Radix behavior primitives where appropriate.
  Reuse the debug console's semantic tokens, typography, density, focus behavior and dark default.
- Build each vertical slice from its smallest page-specific components, compose those into sections,
  then compose the complete page. Review and commit that page before starting the next slice.
- Stories receive serializable view models and injected actions. They do not fetch, import Phoenix,
  require a database, start media capture or connect to RTVI/WebRTC.
- A deterministic navigation harness models the intended browser URLs and back/forward transitions
  without becoming the production router. Links and selected-resource context remain visible and
  reviewable in complete-page stories.
- Each complete page includes loading, empty, populated, unavailable/error, long-content,
  pagination where applicable and narrow-screen states. Unknown and unavailable data never appears
  as an empty successful result.
- Storybook Controls select meaningful fixture states. Do not place a second fake state switcher,
  prototype disclaimer or synthetic-data toolbar inside the product UI.
- Component tests cover Vxpipe-owned interaction and accessibility contracts. Do not duplicate tests
  for behavior guaranteed by React, Radix, Storybook or the browser.
- Tenant navigation is shared presentation, not duplicated page markup. Call Specs, Calls and
  Services are sibling destinations under one tenant. Breadcrumbs retain hierarchy; tenant
  navigation shows the available destinations and current page.
- A checkpoint adds a tenant-navigation destination only with that destination's complete page.
  Intermediate commits contain no dead links, mock placeholders or production routes backed by
  Storybook data.
- Calls belong to the tenant route. A call spec is an optional filter represented in the URL so a
  call spec row can deep-link to the same Calls page without creating another page contract.
- Services exposes only providers already supported by the platform: Google and Zenmux model
  credentials, Deepgram speech credentials, and Telnyx/Twilio telephony configuration. Credential
  values are write-only inputs. Stories never render a stored value, fake masked secret, access key,
  token or provider response payload.
- Adding a supported credential is an operator action in this design. Third-party
  credential rotation schedules, credential reveal, provider discovery and support for new provider
  authentication methods are outside scope. Platform encryption-key rotation remains separate.
- Credential setup is create-only for the `(tenant, provider, name)` binding. A duplicate is shown
  as a conflict and does not overwrite the existing binding; the UI offers no edit or replace action.

## Storybook information architecture

| Intended production URL | Storybook page | Minimum reviewable content |
| --- | --- | --- |
| `/admin` | Tenants | Bounded tenant list, stable identity and navigation to a tenant. |
| `/admin/tenants/:tenant_key` | Tenant workspace entry | Redirects to the tenant's Call Specs destination. |
| `/admin/tenants/:tenant_key/call-specs` | Call Specs | Tenant context and published/draft call spec summaries. |
| `/admin/tenants/:tenant_key/calls` | Calls | Tenant calls with an optional `call_spec_id` filter and a reset to all calls. |
| `/admin/tenants/:tenant_key/services` | Services | Supported AI/telephony service inventory and write-only credential setup. |
| `/admin/tenants/:tenant_key/calls/:call_id` | Call details | Existing debug console populated with ongoing or ended inspection fixtures. |

Tenant creation, call spec editing, provider expansion and demo installation belong to later
milestones. They are not placeholder actions in this Storybook.

## Checkpoint 1 — Complete the Tenants page

- [x] Extend the existing `@vxpipe/react` Storybook with Console-owned admin stories instead of
  adding a second Storybook implementation or server.
- [x] Build the smallest shadcn-compatible components needed for this page: page frame, navigation,
  page header, tenant row/card, list/table, status presentation, skeleton, empty/error state and
  pagination. Keep fixtures and actions outside presentation components.
- [x] Compose the complete Tenants page with loading, empty, populated, unavailable, long-identity,
  paginated and narrow-screen fixtures.
- [x] Make tenant selection navigate through the Storybook harness while preserving a real-link
  affordance and visible destination.
- [x] Test the Vxpipe-owned selection, pagination, empty/error and stale-action behavior.
- [x] Inspect every important state in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate the complete tenant-selection page without a server. Commit this page
slice with its Storybook configuration, frontend tests, documentation and labnotes.

Evidence: deterministic stories cover all required states; the Console's 29 frontend tests,
TypeScript check, ESLint check and Storybook production build pass. Rendered dark/light desktop and
390 px mobile inspection passed without overflow or browser errors. See
[checkpoint labnotes](../20260917-0826-admin-tenants-storybook.md).

## Checkpoint 2 — Complete the tenant call specs page

- [x] Build tenant context and a semantic call spec table with publication state, latest version,
  all-version call count and a filtered Calls link. Do not imply a call spec details destination.
- [x] Compose the complete tenant call specs page with loading, empty, populated, unavailable,
  mixed draft/published, long-name, paginated and narrow-screen fixtures.
- [x] Make each call spec's call count navigate to its filtered Calls page through the Storybook
  harness. Back navigation retains the selected tenant context without depending on a live response.
- [x] Test the Vxpipe-owned selection, publication presentation, pagination and unavailable states.
- [x] Inspect every important state in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate call spec browsing within a selected tenant. Commit this page slice
separately.

Evidence: deterministic stories cover all required states and **Admin / Full journey** connects the
tenant directory to call specs with working breadcrumbs and browser back/forward. A follow-up
contract review confirmed that the platform stores one published revision per call spec; the page
uses `Published`, `Draft`, and `Draft changes` from that state and links call totals to all calls for
the call spec. The Console frontend tests, TypeScript check and warning-free ESLint check pass.
Rendered dark desktop and 390 px mobile inspection confirmed aligned semantic columns and bounded
horizontal table scrolling. See
[checkpoint labnotes](../20260917-0843-admin-definitions-storybook.md) and
[table contract labnotes](../20260917-1236-definition-table-contract.md).

## Checkpoint 3 — Complete the call spec calls page

- [x] Build call spec context, call row/card, lifecycle/archive status and call-list components.
- [x] Compose the complete Call Spec calls page with loading, empty, populated, unavailable,
  ongoing/ended/failed, partial archive, long-value, paginated and narrow-screen fixtures.
- [x] Make call selection navigate through the Storybook harness. Clearly retain both tenant and
  call spec context in the page and navigation.
- [x] Test the Vxpipe-owned selection, status, pagination and unavailable-state contracts.
- [x] Inspect every important state in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate call-spec-scoped call browsing without backend query behavior.
Commit this page slice separately.

Evidence: the calls page covers every lifecycle, independent archive completeness, immutable
call spec revisions, terminal reasons and local timestamps. **Admin / Full journey** now connects
tenants through call specs to calls and records a reload-safe call-details route. The Console's 48
frontend tests, TypeScript check and warning-free ESLint check pass. Rendered dark/light, 390 px,
768 px, 1024 px, long-content, pagination and reduced-motion inspection passed without clipping.
See [checkpoint labnotes](../20260917-0858-definition-calls-storybook.md).

## Checkpoint 4 — Complete the Call details page

- [x] Build only the admin host frame and resource context needed around the existing call console.
  Reuse the real `@vxpipe/react` component rather than copying it.
- [x] Compose the complete Call details page with typed ongoing and ended fixtures plus loading,
  unavailable, partial archive, malformed-response, long-content and narrow-screen host states.
- [x] Preserve the debug console's bounded height, internal scrolling, sticky composer and device/
  timeline/variables/metrics/participants interactions in the composed page.
- [x] Test the host-to-console view-model/action boundary and failure presentation without testing
  `@vxpipe/react` behavior a second time.
- [x] Inspect every important state and scrolling boundary in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate live and historical call inspection inside the complete admin page.
Commit this page slice separately.

Evidence: the admin host reuses the real `@vxpipe/react` CallConsole for interactive ongoing and
read-only ended calls. Deterministic stories cover loading, unavailable, malformed-response and
partial-archive states; **Admin / Full journey** now reaches call details and returns through working
breadcrumbs and browser history. The Console's 54 frontend tests, TypeScript check, warning-free
ESLint check and production Storybook build pass. Rendered dark/light, 390 px and desktop review
verified bounded internal scrolling, composer submission, device controls, every console tab,
reduced motion and failure states. See
[checkpoint labnotes](../20260917-0917-call-details-storybook.md).

Follow-up review compacted the call workspace without adding another page layer: injected call
identity, status, device controls, duration and call action share the console toolbar; conversation
filters share the tab row and collapse into an accessible overflow menu when space is constrained.
The composer is one row and device selection uses compact, keyboard-navigable Floating UI menus.
The React package's 35 tests and Console's 54 tests pass; production Storybook builds, and rendered
390 px, 768 px, 820 px, 901 px and desktop inspection passed. See
[refinement labnotes](../20260917-0958-compact-call-header.md).

A second review made the ready call-details page an edge-to-edge console surface. The reusable
console now accepts a dedicated compact host header and an opt-in borderless fill layout; the admin
host injects its tenant/call spec breadcrumbs there while call identity and partial-history state
remain in the console control row.
Mobile hides the participant rail, lets message identities open participant details, and provides a
participant picker inside that view. Mobile hides the breadcrumb row and places a `Back to calls`
link before call identity in the control row. Status, device controls, duration and the icon-only
call action remain compact. See
[refinement labnotes](../20260917-1207-full-bleed-call-page.md).

The compact-header follow-up opens call details in a separate tab while retaining
the shared `Tenants › tenant › call spec` breadcrumb pattern in the injected bar.
All breadcrumb destinations work in production and the standalone Storybook preview;
no sibling workspace tabs or redundant Call details label are added. Mobile keeps
the breadcrumb context visible. Admin inventories lose their outer boxes and stacked
header/tab rules, retaining active underlines, column-header separators and quieter
row separators. The 122 Console frontend tests, 39 shared package tests and 157
Console ExUnit tests pass, as do TypeScript, ESLint, CSS and Storybook builds.
The umbrella run encountered two gateway failures; both affected files passed a
17-test focused retry, but the umbrella run is not recorded as green. See
[checkpoint labnotes](../20260918-1023-compact-call-header.md).

## Checkpoint 5 — Complete the tenant workspace and Calls page

- [x] Refactor the existing call-spec-scoped call prototype into a tenant Calls page; reuse the
  existing call rows, lifecycle/archive badges, pagination and call-details links.
- [x] Build one focused tenant-workspace navigation component and integrate its working Call
  Specs and Calls destinations. Keep breadcrumbs and route/business logic in their existing
  focused owners; Services is added only with checkpoint 6's complete page.
- [x] Move call specs to `/admin/tenants/:tenant_key/call-specs`, treat the tenant root as its
  Storybook entry redirect, and update call spec links to
  `/admin/tenants/:tenant_key/calls?call_spec_id=:call_spec_id`.
- [x] Default to all tenant calls. Provide a clearly bordered call spec filter populated from the
  tenant's call specs, show the selected call spec without repeating it in descriptive copy, and
  provide a direct reset to all calls.
- [x] Compose all-calls, filtered, no calls, no filter matches, unavailable, loading, partial archive,
  long-content, paginated and narrow-screen stories. Unknown filter identity remains distinct from
  a valid filter with zero matches.
- [x] Keep filtering outside `CallList`; the page receives a serializable state and injected filter,
  pagination and selection actions.
- [x] Test URL/filter synchronization, call spec deep-links, reset, stale actions and truthful
  empty/unavailable states. Cover navigation active state, long tenant names and desktop/mobile
  keyboard operation without making page components own routing.

Exit: a reviewer can browse all calls for a tenant or arrive with one call spec selected, then open
the same call-details console; Call Specs and Calls are fully working sibling destinations.
Commit this page/shell slice separately.

Evidence: one shared tenant navigation links complete Call Specs and Calls pages without a
Services placeholder. Calls default to nine tenant calls, accept an optional `call_spec_id`, and
distinguish tenant-empty, valid-filter-empty, unknown-filter and unavailable results. Call Specs
deep-link to the filtered Calls page; call details retain their existing route. The Console's 62
tests, TypeScript check and ESLint check pass; the React package's 30 tests and the production
Storybook build pass. Rendered desktop, 390 px mobile, filter interaction and unknown-filter review
passed. See [checkpoint labnotes](../20260917-1045-tenant-calls-workspace.md).

## Checkpoint 6 — Complete Services and credential setup

- [x] Define small typed view models for provider credential metadata and telephony service metadata.
  Keep secret input values only in the credential form state and out of fixtures, URL state and list
  rows.
- [x] Build focused service inventory, capability/provider badge, credential status, empty/loading/
  unavailable presentation, and credential setup form components. Do not combine the
  inventory, provider field rules and modal/sheet behavior into one component.
- [x] Limit provider choices and fields to current contracts: API key for Google, Deepgram, Zenmux
  and Telnyx; Account SID plus Auth Token for Twilio. Telephony public configuration is presented
  separately from write-only credential fields.
- [x] Treat existing Telnyx/Twilio telephony service metadata as read-only. Credential creation does
  not register or rebind a telephony service and does not validate provider-side readiness. Show
  “credential stored” separately from configured/verified/ready service status.
- [x] Compose inventory, empty, unavailable, validation-error, submission-pending, save-failure and
  save-success stories. Existing credentials show metadata without showing or pretending to show
  stored values, and do not imply a third-party rotation workflow.
- [x] Test provider-specific field selection, secret clearing after success/cancel, duplicate-name
  conflict without overwrite, repeated submission and tenant-reset state isolation, accessible focus
  restoration and absence of secret values from rendered metadata.
- [x] Inspect dark/light, desktop/mobile and keyboard-only setup flows in rendered Storybook.

Exit: a reviewer can understand which services are configured and safely model adding credentials
for every provider Vxpipe currently supports. The Services link is added to tenant navigation only
with this working page. Commit this page and setup-flow slice separately.

Evidence: the Services page lists Google, Zenmux, Deepgram, Telnyx and Twilio without returning a
secret value. ProviderAuth-compatible local validation precedes an injected create action;
duplicate `(provider, name)` bindings return a conflict and preserve existing metadata. Telephony
rows separately show credential binding identity and read-only registration, provider connection
and outbound-number metadata without claiming provider verification. Deterministic stories cover
inventory, empty, unavailable, validation, pending, failure, conflict, success, long-content,
light and narrow states. The Console's 75 tests, TypeScript check and ESLint check pass; the React
package's 30 tests and production Storybook build pass. Rendered desktop/mobile, dark/light,
long-content, repeated-save and keyboard-modal review passed. See
[checkpoint labnotes](../20260917-1105-tenant-services-storybook.md).

## Checkpoint 7 — Review the complete mocked journey

- [x] Compose one deterministic journey that moves Tenants → Call Specs → filtered Calls →
  Call details and back, and also reaches all Calls and Services through the tenant navigation.
- [x] Verify page context, breadcrumbs, links, back/forward behavior, pagination handoff and state
  isolation across resource changes. No late mock action may replace the currently selected page.
- [x] Review the full journey at representative desktop and mobile viewports, dark/light themes,
  keyboard-only operation, reduced motion and long localized-looking content.
- [x] Build Storybook from a clean checkout and run the focused frontend test suite. Record the exact
  review evidence and any approved design adjustments.
- [x] Present the complete running Storybook journey to the user and record explicit design approval.
  A passing build, automated test or internal review does not grant approval to integrate the app.
- [x] Mark this milestone complete only after that approval, before starting any checkpoint in the
  operator login/admin production-integration milestone.

Exit: the entire first admin application is approved as a coherent mocked experience. Commit the
final Storybook acceptance and synchronize the milestone index.

Technical review evidence: the deterministic Storybook journey at `c016c63` was traversed through
Tenants, Call Specs, call-spec-filtered Calls, Call details, browser back/forward, all tenant
Calls and Services. Rendered review covered 1440 px desktop and 390 px mobile, dark and light themes,
keyboard interactions, reduced-motion emulation and page-specific long-content states. Final review
at `a64fda3` also covered the added Call details long-content story. A separate detached clean
checkout at that commit passed the Console TypeScript check, ESLint check and 76 tests plus the React
package's 30 tests and Storybook 10.6.0 production build after building the local workspaces. All five
umbrella completion gates also pass. Subsequent user-led review refined the compact console, full-page
Call details composition and semantic Call Specs table through `c374fb7`. After those changes,
the user confirmed that the UI is good enough to implement. This explicitly approves the Storybook
design for the next production-integration milestone.
See [acceptance labnotes](../20260917-1139-admin-storybook-acceptance.md).

## Acceptance and completion

- [x] Every intended `/admin` page exists as a complete Storybook page built from its real small
  components and feature sections.
- [x] A reviewer can traverse the full tenant-to-call journey and the tenant Services setup flow
  without Phoenix, a database, network requests, media capture or protocol connections.
- [x] Loading, empty, populated, unavailable/error, long-content, pagination and narrow-screen states
  are reviewable where applicable.
- [x] The Call details page uses the real `@vxpipe/react` console and deterministic typed fixtures.
- [x] Calls defaults to the tenant scope, preserves an optional call spec filter in its URL, and
  links to the same call-details route from filtered and unfiltered states.
- [x] Services supports only current provider contracts and never renders a stored credential value.
- [x] Rendered desktop/mobile, dark/light, keyboard and reduced-motion review passes.
- [x] Storybook build and focused frontend tests pass; no production app/backend integration exists.
- [x] The user has reviewed and explicitly approved the complete Storybook journey.
- [x] Each checkpoint is committed separately with documentation and labnotes.

## Scope boundaries

No login/auth page, Mix task, session, Phoenix admin route, database query, JSON endpoint, production
client, tenant CRUD, call spec editor, new provider/authentication support, third-party credential
rotation, new call-console behavior, package publication or backend contract implementation is
included. Services and credential entry are deterministic Storybook UI contracts only.

## Specification review

Independent GPT 6 Astra xhigh review, 2026-09-17: the original four-page scope separated Storybook
design from auth, backend work, endpoint clients and production routes. The later tenant-navigation,
tenant Calls and Services requirements are split into checkpoints 5–6 before the final review gate;
their downstream production checkpoints must stay synchronized. The review required explicit user
approval before production integration; the user supplied that approval after reviewing the complete
mocked journey and its requested refinements. Specification additions alone did not claim component,
page, rendered-review or production behavior.

Scope-reconciliation review, 2026-09-17: independent GPT 6 Astra xhigh review found no remaining
blockers after each navigation destination was paired with its complete page slice, provider
credential creation received create-only/no-overwrite semantics, and read-only telephony metadata
was separated from stored-credential and provider-readiness status.
