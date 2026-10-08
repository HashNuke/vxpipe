# Console React routing

## Decision

The production Console uses React Router's browser data router (`createBrowserRouter` and
`RouterProvider`). Route
matching, browser-history subscription, redirects, path parameters, and search
parameter synchronization are owned by `react-router`, not by application code.

The route table is:

- `/admin`
- `/admin/onboarding`
- `/admin/tenants/:tenantKey`
- `/admin/tenants/:tenantKey/call-specs`
- `/admin/tenants/:tenantKey/call-specs/new`
- `/admin/tenants/:tenantKey/call-specs/:callSpecId` (`?revision=N` opens read-only)
- `/admin/tenants/:tenantKey/calls`
- `/admin/tenants/:tenantKey/calls/:callId`
- `/admin/tenants/:tenantKey/services`

The tenant workspace root redirects to its Call Specs page. Unknown routes
redirect to `/admin`. Pagination and call-spec filters remain URL search
parameters so links are reloadable and browser navigation restores the selected
view.

The older RTVI playground is a separate `PlaygroundApp` entry point mounted with
the `/admin/samples` basename. Its `/pipecat-console` and `/transfer` child routes also
use React Router, producing `/admin/samples/pipecat-console` and `/admin/samples/transfer`.
Storybook keeps its isolated hash navigation because Storybook runs inside
`/iframe.html` and is not the production application router.

## Alternatives rejected

- The previous pathname regular expressions plus direct `pushState`/`popstate`
  handling duplicated router behavior and made every new page expand a custom
  parser.
- React Router framework mode would take ownership of the build and server model,
  which conflicts with the Phoenix application boundary.
- Declarative mode served the initial navigation migration. The call-spec editor
  now requires `useBlocker` for unsaved changes during browser Back/Forward and
  in-app navigation, so the router uses data mode. Requests retain their explicit
  abort, stale-response and session-expiry contracts; loaders are not required.
  A separate hand-written history blocker was rejected because it would duplicate
  router state and mishandle browser history restoration.

## Implications

- `react-router` is a direct Console asset dependency.
- React Router 8.4 requires Node 22.22 or newer and React 19.2.7 or newer. The
  project uses React 19.3 and declares the higher Node floor.
- Production components navigate through `useNavigate` and render through the
  route table. Storybook-only navigation helpers remain independent.
- Phoenix must continue serving the Console document for its existing `/admin`
  routes so direct browser loads can reach the client router.

## Editor navigation

The editor guards dirty source and pending writes. Its own Back and recovery
actions confirm locally, then bypass the router blocker once for that approved
destination. Other SPA navigation and browser history use the same discard dialog
through `useBlocker`; document reload/close uses `beforeunload`. Successful first
save replaces `/new` with the stored ID without remounting the editor, preserving
edits made while the request was pending. Explicit revision links are read-only
and offer navigation to the latest editable revision. Session expiry during a
write disables authoring and retains the source for copy/download; it does not
redirect away from an unsaved draft.

## Verification

- Route tests cover direct loads, nested parameters, search parameters,
  redirects, browser history, stale request cancellation, and unknown-route
  canonicalization.
- Playground and endpoint tests cover both `/admin/samples` routes and prove the former
  root-level routes are absent.
- TypeScript and ESLint validate the route integration.
