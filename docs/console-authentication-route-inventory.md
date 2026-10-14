# Console authentication route inventory

This inventory records the browser and JSON entry points protected by named user sessions. It is the action map for the authentication
milestone. The map is a review aid; an entry is complete only after the router,
controller and owning Calls/Persistence operation enforce it.

| Entry point | Owning boundary | Required account action |
| --- | --- | --- |
| `/auth/setup`, `/auth/login`, `/auth/recover`, `/auth/logout` | Console and Identity | First-installation bootstrap, anonymous login, or current user session |
| `/admin`, `/admin/*` React shell | Console | Active user session; individual JSON calls check resource actions |
| `/admin/api/session` | Console and Identity | Active user session |
| `/admin/api/users*`, `/admin/api/roles*` | Console and Identity | `users.read` for the directory, exact target-category write for user mutations, built-in actor for role writes |
| `GET /admin/api/tenants` | Calls/Persistence | Explicit `tenants.read`, `tenants.write` or registered tenant operational grants; filter effective scope before count and pagination; unassigned operational roles receive an empty page |
| `/tenants/new`, `POST /admin/api/tenants` | Console and Calls/Persistence | Installation `tenants.write`; create tenant identity without credentials or resource grants; redirect to its permission-aware dashboard |
| `/admin/api/tenants/:key/calls*` | Calls/Persistence | `calls.read` on the resolved tenant; call details, inspection, transcripts and recordings inherit it |
| `/admin/api/tenants/:key/call-specs*` | Calls/Persistence | `call_specs.read` for listing/show, `call_specs.write` for save/publish; platform references require the authoring modifier |
| Tenant providers, service bindings, service directory, telephony application reads, phone numbers | Calls/Persistence | `tenant_services.read` on the resolved tenant |
| Tenant telephony application writes | Calls/Persistence | `tenant_services.write` on the resolved tenant |
| Tenant credentials (`GET /admin/api/tenants/:key/credentials`) and write/test/delete | Calls/Persistence | `tenant_services.read` for reads/testing submitted credentials; `tenant_api_keys.write` for mutations, on the resolved tenant |
| Platform service directory and credentials | Calls/Persistence | `platform_services.read/write` at installation scope |
| Demo onboarding and sample installation | Console and Calls | Built-in administrator; relevant `tenants.write` and `call_specs.write` |
| `/admin/samples/*` and `/admin/samples/calls`, `/transfers` | Console and Calls | Built-in administrator for sample page; `calls.write` for creation on the target tenant |
| `/tenants/:key/calls*` legacy redirects, recording and details | Console and Calls | `calls.read` on the resolved tenant |
| `/admin/diagnostics`, LiveDashboard and socket | Console | Built-in `diagnostics.read`; repeat checks at LiveView/WebSocket entry |

The Console's existing `OperatorTraffic`, CSRF and private-cache controls remain
applicable. `GatewayMount` keeps carrier, participant and independently issued
machine API-key protocols separate from browser identity. Authentication must not
turn an API key or call admission token into a Console user session.

Browser-facing Calls paths accept an explicit user principal and recheck the resource
tenant before retrieval or mutation. Internal `InstallationOperator` compatibility
remains separate; Operational read/write controllers use the user principal. The built-in-only demo
onboarding adapter retains its internal bootstrap authority behind the reserved
`tenants.write` route guard.
Machine-authorized APIs remain independent.

`Vxpipe.Console.RoutePermission` captures the HTTP action map with exact path
patterns and unknown-route denial. The same contract must be checked again by
the final operation owner. Endpoint tests use named sessions and cover role/tenant denials at the HTTP boundary.
