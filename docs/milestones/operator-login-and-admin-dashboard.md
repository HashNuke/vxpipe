# Operator login and admin dashboard

Status: checkpoints 1–3 complete; checkpoints 4–7 remain.
Requested, split and independently reviewed 2026-09-17.
Prerequisites: completed and user-approved
[Operator admin Storybook](operator-admin-storybook.md),
[Tenant administration](tenant-definitions-and-api-keys.md),
[Call inspection](call-inspection-and-debugging.md), and the completed database-snapshot/Core/React
host slices of the in-progress [Call debug console](call-debug-console.md). Its pending live-call
controls and RTVI/WebRTC adapters do not block operator login or historical browsing.
Sources: [Developer console design](../developer-console-and-onboarding.md),
[Gateway/Console boundary](../gateway-console-boundary.md), and
[Call-details model](../debug-console-call-details-model.md).

## Runnable outcome

A trusted operator runs `mix vxpipe.login` and receives a short-lived URL plus a separate
eight-digit code. The URL opens a server-rendered code-entry page. A correct code creates an
operator session and redirects to `/admin`.

The authenticated admin application is React. It lets the operator browse every tenant, move among
one tenant's call definitions, calls and services, optionally filter calls by definition, configure
  credentials for providers Vxpipe already supports, and open an ongoing or ended call in the existing
debug console. This first operator role has installation-wide visibility; it does not introduce
users, teams, tenant memberships or RBAC.

## Product and authority contracts

- Operator browser authority is distinct from platform API keys, tenant API keys, call admission
  tokens and provider credentials. Platform and tenant keys remain programmatic API credentials;
  neither is a UI sign-in credential.
- A valid operator session may inspect every tenant and the resources exposed by this milestone.
  Tenant and definition identifiers select resources; they do not narrow the operator's identity.
- This milestone has one installation-wide operator grant. It adds no user records, email or
  password login, signup, invitations, teams, memberships, roles, RBAC, OIDC or SSO.
- Console owns the login pages, operator session and `/admin` application. Calls owns authorized
  read workflows and repository-neutral result types. Persistence owns schemas, migrations and
  database adapters. Gateway remains reusable and does not acquire Console UI dependencies.
- Calls defines an explicit installation-operator authority accepted only by the bounded admin read
  workflows and the create-only provider-credential mutation. Console passes that authority plus
  selected tenant/resource identifiers; it never fabricates a tenant `Principal`, tenant API-key ID
  or wildcard tenant to reuse existing checks, and it never writes through Persistence directly.
- Anonymous requests and expired sessions disclose no tenant, definition or call data. Missing and
  cross-resource identifiers return the same safe not-found result.
- Lists are bounded and have stable pagination. Empty, loading, unavailable and partial states are
  truthful; the UI never turns an unavailable query into an empty list.
- Provider credential values are accepted only by authenticated, CSRF-protected operator writes and
  are never returned by list/read endpoints. Existing credentials expose metadata only. This
  milestone adds no credential reveal, third-party rotation workflow or new
  provider authentication contract.
- Credential creation preserves the existing unique `(tenant, provider, name)` binding. A duplicate
  returns a conflict without decrypting, replacing or overwriting the stored credential.

## Login challenge and session contracts

- `mix vxpipe.login` uses the configured repository and fails safely when persistence is unavailable
  or migrations are missing. It prints one URL ending in `/auth/login-token/:token` and a separate
  eight-digit decimal code, preserving leading zeroes.
- The URL token contains at least 32 cryptographically random bytes. The code is generated with a
  cryptographically secure source. Store neither plaintext value: store a token digest and a code
  verifier bound to both that token and a deployment secret so a copied database cannot cheaply
  enumerate the 100 million possible codes.
- A challenge expires after 10 minutes, permits at most five incorrect code submissions and is
  consumed atomically. Two concurrent correct submissions produce at most one session. Expired,
  exhausted and consumed challenges cannot be revived.
- Phoenix treats the path token as a filtered parameter and never logs its value. Deployments must
  keep raw URL access logging disabled for this private authentication route because the HTTP server
  and any reverse proxy necessarily receive the token-bearing path. Token and code POST fields are
  redacted before CSRF, controller and project telemetry processing, including error paths.
- `GET /auth/login` is a token-free, server-rendered guidance page that tells a trusted operator to
  run `mix vxpipe.login`; it cannot issue or claim a challenge. Anonymous `/admin` requests and
  expired sessions redirect there.
- `GET /auth/login-token/:token` renders the token into a hidden form field on the server; its
  CSRF-protected `POST /auth/login-token` performs the exchange. No frontend script is required.
  Together with `/auth/login`, they are the only user-facing pages in this milestone that are not
  React. Errors use the same generic wording for an unknown, expired, exhausted or consumed challenge
  and lead back to the token-free guidance page.
- A successful exchange rotates the session identifier and stores only the operator grant,
  issued/absolute-expiry times and an operator-secret authentication tag in the signed session. The tag
  prevents the checked-in development endpoint key from forging operator authority. The initial absolute session
  lifetime is 12 hours with no sliding extension. Sign-out invalidates the browser session and
  redirects to `/auth/login`.
- Cookies are `HttpOnly`, `SameSite=Lax`, and `Secure` when served over HTTPS. Authenticated writes
  retain Phoenix CSRF protection. Login and admin responses use `Cache-Control: private, no-store` and
  `Referrer-Policy: no-referrer`.
- Require HTTPS for operator login and admin traffic outside loopback development. Plain HTTP is
  permitted only for an explicit loopback origin such as `127.0.0.1` or `localhost`; reject other
  HTTP origins rather than issuing a challenge or accepting a login. A same-host reverse proxy may
  supply `X-Forwarded-Proto: https`; forwarded scheme headers from non-loopback peers are ignored.
- The printed origin comes from explicit Phoenix endpoint configuration. The task fails with an
  actionable message if it cannot construct an allowed external HTTP(S) URL.

## React and Storybook contracts

- Do not begin this milestone until every admin page has passed the separate Storybook milestone and
  the user has reviewed and approved the complete mocked journey. Automated checks do not substitute
  for that design approval. Login/auth pages are intentionally absent from the Storybook gate.
- Everything below `/admin` is one React application served by Console. Phoenix provides the HTML
  mount, operator-session guard and JSON endpoints; it does not render admin lists, navigation,
  detail pages or debug-console content.
- Build admin-specific components and page compositions under Console assets. Keep reusable call
  state and call UI in `@vxpipe/core` and `@vxpipe/react`; do not move tenant administration concepts
  into those packages.
- Use shadcn's source-owned composition model and Radix behavior primitives where appropriate.
  Reuse the debug console's semantic color tokens, typography, spacing and dark default rather than
  creating a second visual language. Keep components editable in the repository.
- Reuse the exact components and page contracts approved in the Storybook milestone. Backend
  integration may supply real data/actions and fix integration defects; it does not redesign an
  approved page implicitly. Return material design changes to Storybook for review first.
- The React application owns browser-history navigation under `/admin`. A direct load or refresh of
  any admin URL returns the same authenticated mount and restores the selected page. Links use real
  URLs, preserve browser back/forward behavior and do not depend on in-memory navigation state.
- JSON access stays same-origin and cookie-authenticated. Frontend code receives no API key,
  challenge token, session token or provider secret in HTML configuration, local storage or URLs.
- Page loaders cancel or ignore obsolete requests during navigation. A late response for one tenant,
  definition or call cannot replace the currently selected resource.

## Admin information architecture

| Route | React page | Minimum content |
| --- | --- | --- |
| `/admin` | Tenants | Bounded tenant list, stable identity and link to each tenant. |
| `/admin/tenants/:tenant_key` | Tenant workspace entry | Redirects to the tenant's Call definitions destination. |
| `/admin/tenants/:tenant_key/definitions` | Call definitions | Tenant context and bounded published/draft definition summaries. |
| `/admin/tenants/:tenant_key/calls` | Calls | Bounded tenant calls with an optional `definition_id` filter. |
| `/admin/tenants/:tenant_key/services` | Services | Metadata-only service inventory and write-only credential setup for supported providers. |
| `/admin/tenants/:tenant_key/calls/:call_id` | Call details | Existing live or historical debug console populated from the authorized inspection snapshot. |

Tenant creation, definition editing, provider expansion and demo installation belong to later
milestones and will extend this shell.

## Checkpoint 1 — Persist and issue one login challenge

- [x] Review the challenge/session schema, ownership and secret boundaries before implementation.
- [x] Red-test challenge issuance, token/code digests, leading-zero codes, expiry, restart, five
  failed attempts, atomic consumption, concurrent correct submissions, unavailable persistence and
  rejection of a non-loopback HTTP origin.
- [x] Add the smallest Persistence schema/adapter and Calls contract needed to create and consume a
  challenge. Keep plaintext token/code values out of database fields, logs and inspected structs.
- [x] Implement `mix vxpipe.login` with the configured external origin and protected one-time output.
- [x] Run focused owning-application tests and the relevant migration/restart checks.

Exit: a trusted command issues one durable, expiring challenge whose plaintext exists only in its
one-time output. Commit schema, behavior, tests, documentation and labnotes as one checkpoint.

Implementation evidence, 2026-09-17: Calls owns domain-separated challenge generation and its
repository port; Persistence stores redacted fixed-size digests and atomically consumes or advances
the five-attempt budget under a row lock; Console validates an explicit HTTPS or loopback origin and
prints the URL and code separately. Production requires a 64-byte `SECRET_KEY_BASE`; development
login issuance also requires that explicit secret and never uses the checked-in development endpoint
secret. Calls (89 tests), Persistence (144 tests, 11 excluded) and Console (151 tests, 1 excluded)
pass. Persistence evidence includes concurrent correct submissions, missing-table failure, expiry,
exhaustion, consumed state and attempt-budget survival across Repo restarts. Final common gates and
the follow-up GPT-6 Astra xhigh review passed. Formatting, compilation with warnings as errors,
Credo and unused-dependency checks pass. The full umbrella test run reached one unrelated,
timing-sensitive Telnyx handoff failure (`missing source recovery speech`); its five generated
scenarios passed immediately when rerun in isolation.

## Checkpoint 2 — Exchange the code for an operator session

- [x] Red-test the Phoenix GET/POST flow, CSRF, generic invalid states, attempt exhaustion, atomic
  consumption, session rotation, absolute expiry, sign-out, cache headers, secret filtering and
  rejection of non-loopback insecure traffic.
- [x] Implement the server-rendered `/auth/login` guidance and login/code-entry pages plus the
  operator-session plug. Keep these pages intentionally small; do not bootstrap a second frontend
  application for authentication.
- [x] Protect a minimal `/admin` React mount and its JSON namespace. Anonymous or expired requests
  redirect to login for HTML and return an authorization error for JSON.
- [x] Inspect the login page and authenticated/expired transitions with `agent-browser` at desktop
  and mobile sizes, including keyboard focus and validation errors.

Exit: the command-to-browser flow creates one installation-wide operator session and reaches a
protected empty React mount. Commit the complete authentication slice separately.

Evidence: the server-rendered guidance, token/code exchange, operator-secret-authenticated grant,
12-hour absolute expiry, rotation, sign-out, CSRF, generic failures, secret filtering, cache/referrer
headers, loopback enforcement and same-host proxy trust pass 23 focused tests. The Console suite
passes 169 tests with one integration exclusion; its React assets pass 77 tests, TypeScript and
ESLint. Headless Chrome completed the real `mix vxpipe.login` flow at desktop and mobile sizes,
including sign-out. GPT-6 Astra xhigh independently reviewed the revised backend-rendered token form
and found no checkpoint blocker. Raw URL logging remains an explicitly documented deployment boundary.

## Checkpoint 3 — Browse tenants through the React application

- [x] Red-test a bounded installation-wide tenant-summary query and operator-only Console JSON
  endpoint, including pagination, empty data, persistence failure and anonymous access.
- [x] Introduce the Calls-owned installation-operator read authority used by each admin query. Prove
  Console does not synthesize a tenant principal or API-key identity.
- [x] Connect the approved Tenants Storybook page to the real endpoint through a typed Console-owned
  client/validator. Keep component inputs identical to their mocked story inputs.
- [x] Implement `/admin` browser-history navigation, refresh restoration and session-expiry handling.
- [x] Prove loading, empty, populated, unavailable and stale-response behavior in component tests and
  rendered browser inspection.

Exit: an authenticated operator can browse all tenants in the real React admin application. Commit
the query, endpoint, React integration, tests, docs and labnotes together.

Evidence: Calls accepts only its explicit installation-operator authority and returns validated,
bounded tenant pages through the repository-neutral admin port. Persistence reads each page and its
total in one statement, ordered by creation time and stable key; Console exposes the operator-session-only endpoint and maps the response
through a typed validator into the approved Tenants page. Browser history stores the page in the URL,
refresh restores it, expired sessions return to login, and obsolete responses cannot replace a newer
page or expire the current session. Structured and out-of-range pages fail safely; the React client
recovers an out-of-range URL and rejects contradictory pagination metadata. Calls (93 tests),
Persistence (146 tests, 11 excluded), Console (172 tests, one excluded), and Console assets (84 tests)
pass. Headless Chrome verified the real login-to-directory flow, desktop and
mobile layouts, page-two refresh, back navigation, and rendered populated, empty and unavailable
states. Browser inspection caught a missing query parser before completion; the literal-query endpoint
test now covers it. Formatting, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass. GPT-6 Astra xhigh approved the final checkpoint after reviewing persistence consistency,
failure handling, pagination validation and stale-request behavior. The umbrella run reached one
unrelated Call Engine live-inspection failure after 698 tests;
that unchanged test also fails alone because killing its inspection buffer removes the participant it
then expects to remain.

## Checkpoint 4 — Browse one tenant's definitions and workspace

- [ ] Red-test a bounded tenant-definition summary query and endpoint with stable pagination,
  current publication state, missing tenant and persistence failure.
- [ ] Connect the approved Tenant definitions page without changing its presentation contract.
  Preserve tenant context in navigation and reject a stale response after switching tenants.
- [ ] Move the destination to `/admin/tenants/:tenant_key/definitions`. The tenant root redirects
  there without losing the selected tenant; Calls and Services links are not exposed yet.
- [ ] Verify direct URL load, refresh, back/forward, empty/populated/unavailable states and long
  definition names in automated and rendered browser checks.

Exit: an authenticated operator can select any tenant and browse its call definitions. Commit this
vertical slice separately.

## Checkpoint 5 — Browse tenant calls with an optional definition filter

- [ ] Red-test a bounded tenant call-summary query whose optional definition filter matches the exact
  definition identity across immutable revisions. Another tenant's call or definition never appears.
- [ ] Expose the operator-only endpoint and connect the approved Calls page, including optional
  `definition_id`, filter reset, lifecycle/archive status, pagination and truthful unavailable fields.
- [ ] Connect the approved shared tenant navigation with working Call definitions and Calls
  destinations. Do not expose Services until checkpoint 6 supplies its page and endpoints.
- [ ] Verify direct URL load, refresh, back/forward, empty/populated/unavailable data, stale-response
  protection and cross-resource failures.

Exit: an operator can browse all tenant calls or follow a definition deep-link to the same page with
that definition selected. Commit this vertical slice separately.

## Checkpoint 6 — Manage supported tenant services

- [ ] Red-test metadata-only provider credential and telephony service reads under installation-
  operator authority, including tenant isolation, stable ordering and unavailable persistence.
- [ ] Red-test CSRF-protected credential-add endpoints for the current Google, Deepgram,
  Zenmux, Telnyx and Twilio auth contracts. Responses and logs contain metadata only; rejected and
  successful writes never echo secret fields.
- [ ] Add the smallest Calls-owned installation-operator credential workflow around the existing
  repository port. It is create-only and returns a duplicate conflict without overwriting; Console
  never invokes Persistence or the trusted-host-only provisioning API directly.
- [ ] Connect the approved Services inventory and provider-specific setup flow. Keep form state and
  endpoint validation outside list/presentation components, and clear secret inputs after cancel,
  error recovery and success.
- [ ] Add Services to the shared tenant navigation only after its page and endpoints work. Existing
  telephony service metadata is read-only: adding Telnyx/Twilio credentials does not register or
  rebind a telephony service or prove provider-side readiness. Report stored-credential status
  separately from configured/verified/ready service state.
- [ ] Verify direct URL load, refresh, back/forward, loading/empty/unavailable states, duplicate
  names, stale submissions, session expiry and cross-tenant identifiers in automated and
  rendered browser checks.

Exit: an authenticated operator can inspect service metadata and add credentials for providers
Vxpipe already supports without any secret-read path. Commit this vertical slice separately.

## Checkpoint 7 — Open live and historical call details

- [ ] Replace the old tenant-API-key browser authority on all Console call-inspection resources with
  the operator session. Preserve tenant/call lookup isolation and `private, no-store` responses.
- [ ] Connect the approved Call details page to the existing inspection snapshot. Hand validated
  data to `@vxpipe/core`; keep endpoint fetching and operator routing outside reusable packages.
- [ ] Render ongoing, ended, partial archive, unavailable and malformed snapshot states. Existing
  RTVI/WebRTC live attachment remains governed by the call-debug-console milestone.
- [ ] Verify direct links, session expiry, another tenant's call ID, desktop/mobile scrolling and the
  existing debug-console interactions in automated and rendered browser checks.
- [ ] Retire `/operator/sign-in` and `/operator/session`. Reject and clear the legacy tenant-session
  cookie; it never upgrades into the installation-wide operator grant. Keep tenant API
  authentication itself unchanged.
- [ ] Redirect the old tenant call-list, LiveView call-detail and `/console` HTML URLs to their exact
  `/admin` destinations after operator authentication. Retain the inspection JSON, call-details
  download and recording artifact URLs only as operator-session-protected resource endpoints used
  by the React page; they render no independent UI.

Exit: the React admin application opens any authorized live or historical call in the same debug
console. Commit this migration separately.

## Acceptance and completion

- [ ] `mix vxpipe.login` produces one short-lived URL and separate eight-digit code; only digests
  persist, and expiry/attempt/concurrency behavior passes after application restart.
- [ ] The Phoenix-rendered auth flow is the only non-React user page introduced here. Every `/admin`
  page comes from the completed and explicitly user-approved Storybook milestone.
- [ ] One operator session sees every tenant, definition and tenant call without user, team,
  membership or RBAC records.
- [ ] Tenant Calls defaults to all calls and accepts an isolated definition filter; shared tenant
  navigation reaches Call definitions, Calls and Services on direct load and through browser history.
- [ ] The Services page lists metadata and accepts supported provider credentials through write-only,
  CSRF-protected actions; no endpoint or UI reveals stored credential values.
- [ ] Platform and tenant API keys remain API credentials and cannot sign into the UI.
- [ ] Anonymous, expired and cross-resource requests disclose no administration or call data.
- [ ] Direct loads, refresh and browser history work for every admin URL; lists remain bounded and
  unavailable states remain distinct from empty data.
- [ ] Focused Elixir/TypeScript tests, Storybook build, rendered desktop/mobile checks and all common
  umbrella gates pass. Each passing checkpoint is committed with its docs and labnotes.

## Scope boundaries

No user directory, email/password authentication, password reset, signup, invitation, team,
membership, RBAC, OIDC/SSO, audit identity, tenant CRUD, definition editor, new provider/auth method,
API-key redesign, billing, credential reveal, third-party credential rotation schedule, package
publication or container release is included.

## Specification review

Independent GPT 6 Astra xhigh review, 2026-09-17: the revised checkpoints are suitably bounded and
put every complete admin page through component-first Storybook review before backend integration.
Review findings added the token-free auth destination, explicit HTTPS/loopback rule, Calls-owned
operator authority, legacy route/session cutover, and clarified debug-console prerequisite. React
ownership, installation-wide visibility and exclusion of users/RBAC/API-key UI login are clear.
Specification only: no implementation, migration, Storybook page or acceptance is claimed.

Split-plan review, 2026-09-17: the original four-page plan was independently reviewed. Later user
direction adds shared tenant navigation, tenant-wide Calls and Services credential setup; these now
have matching Storybook and production checkpoints. Auth remains outside Storybook. The production
milestone was initially gated on explicit approval of the complete mocked journey; the user cleared
that gate on 2026-09-17 after reviewing and refining the Storybook UI.

Scope-reconciliation review, 2026-09-17: independent GPT 6 Astra xhigh review found no remaining
blockers. Calls owns the bounded installation-operator credential mutation, duplicates cannot
overwrite an existing binding, navigation activates only with working destinations, and existing
telephony service metadata remains read-only and distinct from credential/provider readiness.
