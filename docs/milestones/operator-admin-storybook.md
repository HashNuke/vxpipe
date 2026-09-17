# Operator admin Storybook

Status: planned, not implemented. Requested and independently reviewed 2026-09-17.
Prerequisites: the private React package and completed component/model slices of the in-progress
[Call debug console](call-debug-console.md).
Sources: [Developer console design](../developer-console-and-onboarding.md),
[React styling contract](../react-component-styling.md), and
[Call-details model](../debug-console-call-details-model.md).

## Runnable outcome

The Console Storybook presents the complete operator administration experience with deterministic
mock data. A reviewer can move from the tenant list to one tenant's definitions, then to a
definition's calls, and finally to the existing debug console for an ongoing or ended call.

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
- Console owns an admin Storybook that consumes the same component exports the production React
  application will later use. The production app must not receive a second implementation.
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

## Storybook information architecture

| Intended production URL | Storybook page | Minimum reviewable content |
| --- | --- | --- |
| `/admin` | Tenants | Bounded tenant list, stable identity and navigation to a tenant. |
| `/admin/tenants/:tenant_key` | Tenant definitions | Tenant context and published/draft definition summaries. |
| `/admin/tenants/:tenant_key/definitions/:definition_id` | Definition calls | Definition context/current revision and calls across its revisions. |
| `/admin/tenants/:tenant_key/calls/:call_id` | Call details | Existing debug console populated with ongoing or ended inspection fixtures. |

Tenant creation, definition editing, provider credential entry and demo installation belong to later
milestones. They are not placeholder actions in this Storybook.

## Checkpoint 1 — Complete the Tenants page

- [ ] Add the Console Storybook and its build/test commands without duplicating the existing
  `@vxpipe/react` Storybook implementation.
- [ ] Build the smallest shadcn-compatible components needed for this page: page frame, navigation,
  page header, tenant row/card, list/table, status presentation, skeleton, empty/error state and
  pagination. Keep fixtures and actions outside presentation components.
- [ ] Compose the complete Tenants page with loading, empty, populated, unavailable, long-identity,
  paginated and narrow-screen fixtures.
- [ ] Make tenant selection navigate through the Storybook harness while preserving a real-link
  affordance and visible destination.
- [ ] Test the Vxpipe-owned selection, pagination, empty/error and stale-action behavior.
- [ ] Inspect every important state in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate the complete tenant-selection page without a server. Commit this page
slice with its Storybook configuration, frontend tests, documentation and labnotes.

## Checkpoint 2 — Complete the Tenant definitions page

- [ ] Build tenant context, definition row/card, publication-state and definition-list components.
- [ ] Compose the complete Tenant definitions page with loading, empty, populated, unavailable,
  mixed draft/published, long-name, paginated and narrow-screen fixtures.
- [ ] Make definition selection navigate through the Storybook harness. Back navigation retains the
  selected tenant context without depending on a live response.
- [ ] Test the Vxpipe-owned selection, publication presentation, pagination and unavailable states.
- [ ] Inspect every important state in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate definition browsing within a selected tenant. Commit this page slice
separately.

## Checkpoint 3 — Complete the Definition calls page

- [ ] Build definition context, call row/card, lifecycle/archive status and call-list components.
- [ ] Compose the complete Definition calls page with loading, empty, populated, unavailable,
  ongoing/ended/failed, partial archive, long-value, paginated and narrow-screen fixtures.
- [ ] Make call selection navigate through the Storybook harness. Clearly retain both tenant and
  definition context in the page and navigation.
- [ ] Test the Vxpipe-owned selection, status, pagination and unavailable-state contracts.
- [ ] Inspect every important state in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate definition-scoped call browsing without backend query behavior.
Commit this page slice separately.

## Checkpoint 4 — Complete the Call details page

- [ ] Build only the admin host frame and resource context needed around the existing call console.
  Reuse the real `@vxpipe/react` component rather than copying it.
- [ ] Compose the complete Call details page with existing ongoing and ended fixtures plus loading,
  unavailable, partial archive, malformed-response and narrow-screen host states.
- [ ] Preserve the debug console's bounded height, internal scrolling, sticky composer and device/
  timeline/variables/metrics/participants interactions in the composed page.
- [ ] Test the host-to-console view-model/action boundary and failure presentation without testing
  `@vxpipe/react` behavior a second time.
- [ ] Inspect every important state and scrolling boundary in rendered desktop/mobile Storybook.

Exit: a reviewer can evaluate live and historical call inspection inside the complete admin page.
Commit this page slice separately.

## Checkpoint 5 — Review the complete mocked journey

- [ ] Compose one deterministic journey that moves Tenants → Tenant definitions → Definition calls
  → Call details and back through the same components used by the individual page stories.
- [ ] Verify page context, breadcrumbs, links, back/forward behavior, pagination handoff and state
  isolation across resource changes. No late mock action may replace the currently selected page.
- [ ] Review the full journey at representative desktop and mobile viewports, dark/light themes,
  keyboard-only operation, reduced motion and long localized-looking content.
- [ ] Build Storybook from a clean checkout and run the focused frontend test suite. Record the exact
  review evidence and any approved design adjustments.
- [ ] Present the complete running Storybook journey to the user and record explicit design approval.
  A passing build, automated test or internal review does not grant approval to integrate the app.
- [ ] Mark this milestone complete only after that approval, before starting any checkpoint in the
  operator login/admin production-integration milestone.

Exit: the entire first admin application is approved as a coherent mocked experience. Commit the
final Storybook acceptance and synchronize the milestone index.

## Acceptance and completion

- [ ] Every intended `/admin` page exists as a complete Storybook page built from its real small
  components and feature sections.
- [ ] A reviewer can traverse the full tenant-to-call journey without Phoenix, a database, network
  requests, media capture or protocol connections.
- [ ] Loading, empty, populated, unavailable/error, long-content, pagination and narrow-screen states
  are reviewable where applicable.
- [ ] The Call details page uses the real `@vxpipe/react` console and existing fixtures.
- [ ] Rendered desktop/mobile, dark/light, keyboard and reduced-motion review passes.
- [ ] Storybook build and focused frontend tests pass; no production app/backend integration exists.
- [ ] The user has reviewed and explicitly approved the complete Storybook journey.
- [ ] Each checkpoint is committed separately with documentation and labnotes.

## Scope boundaries

No login/auth page, Mix task, session, Phoenix admin route, database query, JSON endpoint, production
client, tenant CRUD, definition editor, credential UI, new call-console behavior, package publication
or backend contract implementation is included.

## Specification review

Independent GPT 6 Astra xhigh review, 2026-09-17: all four admin pages have matching Storybook and
production-integration checkpoints. The Storybook scope excludes auth, backend work, endpoint
clients and production routes; the complete mocked journey requires explicit user approval before
the production milestone can begin. Dependency order and route coverage are clear. Specification
only: no component, page, rendered review, test result, user design approval or production behavior
is claimed.
