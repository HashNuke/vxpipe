# Console React routing

## Decision

The production Console uses React Router's declarative browser router. Route
matching, browser-history subscription, redirects, path parameters, and search
parameter synchronization are owned by `react-router`, not by application code.

The route table is:

- `/admin`
- `/admin/onboarding`
- `/admin/tenants/:tenantKey`
- `/admin/tenants/:tenantKey/definitions`
- `/admin/tenants/:tenantKey/calls`
- `/admin/tenants/:tenantKey/calls/:callId`
- `/admin/tenants/:tenantKey/services`

The tenant workspace root redirects to its definitions page. Unknown routes
redirect to `/admin`. Pagination and call-definition filters remain URL search
parameters so links are reloadable and browser navigation restores the selected
view.

The older RTVI playground is a separate `PlaygroundApp` entry point mounted with
the `/samples` basename. Its `/pipecat-console` and `/transfer` child routes also
use React Router, producing `/samples/pipecat-console` and `/samples/transfer`.
Storybook keeps its isolated hash navigation because Storybook runs inside
`/iframe.html` and is not the production application router.

## Alternatives rejected

- The previous pathname regular expressions plus direct `pushState`/`popstate`
  handling duplicated router behavior and made every new page expand a custom
  parser.
- React Router framework mode would take ownership of the build and server model,
  which conflicts with the Phoenix application boundary.
- Data mode was unnecessary for this migration because Console requests already
  have explicit abort, stale-response, and session-expiry behavior. Declarative
  mode replaces navigation without rewriting those integration contracts.

## Implications

- `react-router` is a direct Console asset dependency.
- React Router 8.4 requires Node 22.22 or newer and React 19.2.7 or newer. The
  project uses React 19.3 and declares the higher Node floor.
- Production components navigate through `useNavigate` and render through the
  route table. Storybook-only navigation helpers remain independent.
- Phoenix must continue serving the Console document for its existing `/admin`
  routes so direct browser loads can reach the client router.

## Verification

- Route tests cover direct loads, nested parameters, search parameters,
  redirects, browser history, stale request cancellation, and unknown-route
  canonicalization.
- Playground and endpoint tests cover both `/samples` routes and prove the former
  root-level routes are absent.
- TypeScript and ESLint validate the route integration.
