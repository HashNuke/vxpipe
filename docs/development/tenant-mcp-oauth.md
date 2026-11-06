# Outbound tenant MCP OAuth

Status: authorization-request builder, durable attempt store and Calls authorization
boundary plus registration/token adapters implemented. Connect/callback orchestration and initial credential persistence are wired.
Grant refresh coordination, reconnect replacement and saved-registration reuse
are wired. Production forms and nonsecret return recovery are implemented; real
browser/provider and independent-node acceptance remain open. See the focused
[UI contract](mcp-oauth-ui.md), [browser flow](mcp-oauth-browser-flow.md),
[renewal contract](mcp-oauth-renewal.md) and [saved runtime](saved-mcp-runtime.md).
This is part of
[the integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md),
not the existing inbound MCP authorization server.

## Ownership and dependency decision

Console owns browser-session authorization and the existing installation callback
identity at `/oauth/mcp/callback`. Calls owns tenant permissions and repository ports.
Persistence owns durable attempts and encrypted grant state. MCP owns protocol
validation, client registration, authorization request construction and token HTTP.

The installed ExMCP `FullOAuthFlow.execute/1` performs discovery, registration and
exchange together and starts its own callback listener. `OAuthFlow.start_authorization_flow/1`
registers replay state in the library's node-local GenServer. Neither is the owner
for a Console browser flow whose callback may reach another instance or arrive
after a process restart. Calling the full flow on URL entry was also rejected
because discovery must have no registration/token side effects.

Reuse ExMCP's PKCE implementation, endpoint validators, registration policy/request
primitives and hardened metadata/OAuth HTTP boundaries. Vxpipe supplies the durable
attempt lifecycle rather than treating a node-local transaction as cross-node replay
protection. Do not bypass network policy with a separate generic HTTP client.
The installed SecureHTTP default permits loopback HTTP, so production callers must
explicitly disable that option and fix request/response/time limits.

## Runtime transport credential patch

The pinned ExMCP revision resolves provider credentials for POST, but originally
captured headers for GET/SSE reconnects and session DELETE. This could reuse an
expired token or bypass a saved connection's revocation check. The reviewed patch
in `patches/ex_mcp/runtime-request-credentials.patch` resolves GET headers before
each connection/reconnect and resolves credentials before DELETE. A revoked
credential skips remote deletion while allowing local stream cleanup to finish.
The Vxpipe provider emits a fixed rejection signal on failed resolution. The
patch converts it to an HTTP submission error, while SSE terminates with redacted
status; neither path can fall back to old headers. The fixed client profile accepts only this guarded runtime provider.
Packaged Gateway call startup now builds a fresh saved-tenant snapshot and attaches
the provider to each selected MCP binding, including legacy incoming admission.
Prepared plans and managed startup descriptors remain credential-free. Complete
current static/OAuth request headers resolve privately at each submission, with
no token/header copies in the binding. Startup checks operation/configured-source
compatibility; submissions resolve through the configured source and recheck tenant,
connection, generation, endpoint and authentication method.

`bin/setup` applies the patch and compiles ExMCP for development and test. CI
applies it before compilation. Other clean build/release pipelines must run
`bin/patch-ex-mcp` after `mix deps.get` and then `mix deps.compile ex_mcp` in their
build environment. The script verifies the exact pinned Git revision, patch
checksum and all three source files. Reapplication is idempotent; unknown local source
changes fail without overwriting them. On an ExMCP upgrade, review the patch and
regenerate its manifest deliberately; do not bypass the checksum failure.

A narrow tracked patch preserves the pinned transport and its streaming limits.
Disabling SSE would remove required behavior. A wrapper transport was rejected
because ExMCP's client paths depend on the HTTP module and state struct. Broad
vendoring would add unrelated source ownership. Prefer removing this patch when
a reviewed upstream revision provides equivalent behavior.

Verification includes clean local checkout application, idempotence, tampered
patch/source rejection, and actual loopback HTTP assertions for the initial SSE
token, renewed reconnect token and current DELETE token. Revocation tests assert
failure before DNS. These checks do not prove cross-node active-call revocation;
the full saved-record publication-to-execution acceptance gates remain open.

## Authorization request foundation

### Shared-callback issuer requirement

Implemented decision (2026-11-06): delegated authorization through the
shared installation callback requires advertised
`authorization_response_iss_parameter_supported: true` and an exact matching `iss`
in every authorization response. Reject absent/false capability before DCR,
authorization handoff or token exchange. Report an unsupported OAuth capability;
do not silently fall back to accepting a response without issuer identification.
This compatibility requirement applies to managed and Own-client authorization
code flows. Client-credentials grants have no browser response and are unaffected.

The installation can connect to multiple independently controlled issuers.
Session-bound state and PKCE are necessary but do not replace issuer identification
at this boundary. The former optional-issuer validation was insufficient
for enabling the production flow. RFC 9700 sections 2.1 and 4.4.2 require mix-up
defense for multi-server clients and recommend authorization-response issuer
identification. Its section 4.4.2.2 also describes a dynamic-registration bypass of
the distinct-redirect alternative. See
[OAuth security BCP](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.4.2).

Rejected alternatives: treating state as issuer proof, trusting only the stored
token endpoint, or adding issuer-hashed callback URLs to CIMD/DCR metadata without
addressing that registration bypass. Supporting providers without RFC 9207 would
require a separately verified issuer-bearing response mechanism, such as signed
JARM or OIDC response processing; neither is implemented by this milestone's
authorization-code adapter. A generic callback exception must not enable it.

Verification: absent/false/malformed capability fails before registration;
missing/mismatched callback issuer fails before code redemption, even for a stored
attempt with the previous optional flag; exact issuer success and consent denial
remain supported. Preflight reports `unsupported_oauth` with no suggested method;
the production dialog explains the unsupported security requirements without
starting a browser round trip or implying anonymous access. The shared capability
validator also requires S256 and authorization-code support. MCP suite: 93 tests;
Console suite: 446 tests; focused discovery/dialog suite: seven tests, all passing.
Full OAuth workflow/interoperability acceptance is still pending.

`Vxpipe.MCP.OAuthAuthorization` accepts validated issuer metadata, client ID and
installation origin/resource/scopes. It derives the callback from ClientMetadata,
requires advertised S256 and authorization-code capabilities, and uses ExMCP's
verifier/challenge primitives. It generates 32 random bytes for state. Endpoint
queries cannot override response type, client, callback, scope, resource, state or
PKCE; duplicated query keys are rejected. Scope tokens and input sizes are bounded.

The returned struct is private and opaque to generic inspection. Only its
`authorization_url` is suitable for browser handoff. State and verifier must be
stored in the encrypted attempt before returning that URL; they must not be logged
or sent in a public connection payload. Three focused tests pass (seed 627127).
This pure builder performs no network request and creates no durable attempt.

## Durable attempt foundation

`Persistence.MCP.OAuthAttemptStore` stores hashed state and encrypted payloads with
an authenticated tenant/attempt identity. The payload also authenticates the stored
connection, generation, issuer, resource and browser/installation bindings. Tenant
locking bounds active attempts to eight; expiry is at most ten minutes. Claim uses
a database row lock and verifies session, user, installation revision and exact
callback before consuming the attempt and erasing ciphertext. Missing encryption
keys roll back without creating records.

`Calls.MCPOAuthAttempts` checks tenant write permission and tenant existence, then
refreshes browser authority immediately before repository operations. User/session
bindings come from the principal. Installation identity and protocol attributes are
trusted server-workflow inputs, not a public JSON interface. Callback scope lookup now resolves a tenant only for matching state digest and
browser user/session while the attempt is unexpired and unclaimed. Calls then
checks current tenant authority, loads the exact installation callback and claims
atomically. The Console callback now invokes this claim boundary before redemption. Cross-node,
retention and key-rotation acceptance are still pending.

## Callback validation foundation

`MCP.OAuthCallback` parses the raw query before framework map conversion can hide
repeated parameters. It bounds input, requires state and exactly one code/error,
keeps the result opaque to inspection and discards provider error descriptions.
Validation requires an exact response issuer match, including for attempts saved
with the former optional-issuer flag. Discovery requires advertised response-issuer
support before authorization-code preparation. These checks follow
[RFC 9207 §2.4](https://www.rfc-editor.org/rfc/rfc9207.html#section-2.4).

This parser does not authenticate state or redeem codes. The callback route binds
and consumes the durable attempt before exchange. Issuers without response-issuer
support are rejected under the shared-callback policy above; there is no optional
`iss` compatibility path. Full interoperability acceptance remains open.

## Token exchange foundation

`MCP.OAuthTokenExchange` uses ExMCP SecureHTTP directly for pinned token HTTP.
Preserving raw token-response field presence is necessary for validation; the
HTTPClient's normalized result would hide absent-versus-defaulted distinctions. It accepts only the fixed authorization-code fields and
explicit public-client, client-secret-basic, client-secret-post or registered
private-key JWT authentication.
Production policy disables loopback/private hosts and redirects, bounds request
and response sizes and uses fixed timeouts. It performs one request, with no retry
on transport ambiguity or provider rejection. Provider bodies become fixed errors;
validated bearer credentials are returned in an opaque struct.

The caller must supply endpoints from the validated attempt, check response issuer
and consume state before exchange. MCP initialization and complete bounded tools
validation must succeed before connection/grant persistence; the authorization
attempt is already durable before browser handoff.
Calls/Console implement that orchestration and durable refresh coordination; the
token adapter itself remains a single-request protocol boundary.

## Registration foundation

`MCP.OAuthRegistration` has explicit CIMD and DCR entry paths. CIMD requires the
advertised capability and returns this installation's metadata-document URL as the
client ID without registration HTTP. DCR builds managed web-client metadata through
ExMCP and submits one bounded pinned request; an optional initial access token is
sent only as the registration Authorization header. Response callback URLs must
match the installation callback and token authentication must match the requested
supported method. Public clients, secret-basic and secret-post are supported.
Credentials remain in an opaque result; provider bodies do not escape errors.

Connect invokes registration only after authorization and fresh metadata validation.
Registration is not invoked by URL preflight. Expiry and saved-registration reuse
are implemented as described below. Local HTTP/database interoperability is covered;
authenticated browser/provider and independent-node acceptance remain open.

## Connect preparation foundation

`MCP.OAuthPreparation` composes fresh protected-resource and selected-issuer
metadata discovery with capability validation, managed registration and authorization
request construction. Its closed input accepts the MCP URL, draft revision, selected
method/issuer and optional DCR initial token; browser OAuth endpoint overrides are
rejected. Registration happens only after the authorization builder validates
capabilities, so unsupported PKCE does not create a remote client.

The private result contains registration credentials, authorization state/verifier,
validated token endpoint and issuer-response requirement. `Calls.MCPOAuthAttempts.start` now owns the authorization-to-persistence sequence
through a protocol preparation port. It rechecks installation identity after remote
work and returns only the URL plus opaque attempt/connection IDs after successful
persistence. Console now wires POST `/api/tenants/:tenant_key/mcp-oauth` through the session
product pipeline with tenant write permission and CSRF. Its preparation adapter
uses the bounded runner, and the runtime repository is the encrypted attempt store.
Installation origin/revision are read freshly from identity storage rather than
request headers or cached browser state. Grant refresh and production forms are
implemented; authenticated browser and independent-node acceptance remain open.

## Completion foundation

`Console.MCPOAuthCompletion` accepts a claimed private attempt, validates callback
issuer, redeems its code once, then runs MCP initialization/tool discovery with the
returned bearer token. Only a successful check produces a private resolved OAuth
connection. It discards the consumed PKCE verifier, retains registration/token
inputs for encrypted persistence and derives token expiry from the response.
`ConnectionStore.create_oauth` preserves the attempt's connection UUID and encrypts
initial credentials with the existing tenant/configuration-bound envelope.

The session-only GET `/oauth/mcp/callback` parses the raw query, claims state and
invokes completion. Calls checks installation identity and current tenant permission
again before saving credentials. Success redirects to the tenant Integrations page
with no code/token in the destination; responses are private/no-store and suppress
referrers. Errors expose fixed codes. Grant revision, refresh coordination and
generation-checked replacement are implemented below; full interoperability and
cross-node lifecycle acceptance remain open.

## Refresh persistence foundation

`Persistence.MCP.OAuthGrantStore` stores refresh claims and grant revisions inside
this connection's encrypted credential envelope. A row lock admits one claim for
the observed grant/configuration revisions. A successful refresh atomically replaces
only token fields and advances grant revision; configuration generation remains
unchanged. Revocation/replacement changes configuration authority and fences an old
worker. Omitted refresh tokens preserve the current token; token responses cannot
change registration/client identity.

Claims expire after thirty seconds but are never reclaimed for another network
attempt: a worker may have already consumed a rotating token. An expired claim
requires reconnect. This is a durable ambiguity fence, not a retry lease. `Calls.MCPOAuthRefresh` now claims before one network exchange through Console's
adapter, commits only token fields, and fences any failed/ambiguous exchange for
reconnect. Omitted refresh tokens preserve the saved rotating token. This is a
trusted runtime port whose caller owns authorization; it is not a public refresh
API. Runtime integration and distinct PostgreSQL-session race checks are
implemented; separate-BEAM-node acceptance remains open.

## Runtime credential boundary and rejected fallback

`Calls.MCPRuntimeCredentials` resolves only the exact tenant/connection/configuration
generation. OAuth grants near expiry refresh once and are resolved again from
storage; registration/refresh secrets never enter transport bindings. The guarded
provider resolves complete current request headers privately. Pending/failed
refresh claims never fall back to an old token. Unknown methods, stale identity,
revocation and invalid expiry fail closed. It is a trusted runtime port, not a
public credential API; callers still own authorization to use the connection.

Source inspection found that installed ExMCP `Transport.HTTP.apply_provider_token`
retains the prior transport state on provider errors, and its provider path can
retry after a challenge. Therefore wiring the existing auth-provider hook directly
would violate the required fail-closed/no-ambiguous-retry behavior. Reject that
shortcut. The guarded runtime provider and reviewed three-file transport patch
now resolve credentials before submission and reject failures without fallback.
Saved catalog/picker/startup wiring is implemented. Explicit embedded application
configuration remains a separate boundary; full per-admission/transfer and
separate-node execution acceptance remain open.

## Guarded provider decision

`MCP.RuntimeAuthProvider` implements the existing provider contract with one crucial
adaptation: a failed resolution exits the submitting process with a fixed reason
instead of returning an error tuple that ExMCP would ignore. It validates the token,
checks the pinned method and never grants a 401/403 retry. Tests call the actual
ExMCP HTTP `send_message` entry point with an old token installed and demonstrate
that failure occurs before DNS/HTTP submission. The opaque state prevents generic
inspection from revealing resolver data.

The guarded provider is wired through production ClientOptions. Initial inspection
also found deferred GET/SSE paths retaining headers, which the pinned patch above
now covers along with session DELETE. Initial static credentials alone would not
solve refresh/reconnect. Keep SSE enabled and preserve zero-network rejection plus
local cleanup; tagged HTTP tests cover the actual request paths. This evidence
still does not establish cross-node active-call revocation.

## Required durable workflow

The following describes the implemented durable workflow. Fixture and database
checks do not close the separate authenticated browser and independent-node gates:

- Connect validates current session/tenant write permission, endpoint/resource and
  selected issuer, then performs the selected registration mechanism. CIMD uses
  installation metadata; protected DCR accepts only its optional initial access token.
- Persist an expiring attempt bound to tenant, user, browser session, stable connection
  ID, expected generation, issuer, resource, installation URL revision, exact callback
  and draft revision. Store only a state digest for lookup; encrypt verifier and any
  registration secrets with the installation keyring and attempt-specific identity.
- A callback claims the matching attempt atomically in the database. Session/tenant,
  issuer, expiry and installation revision must match. A claimed attempt cannot be
  replayed on another instance. A lost/ambiguous token response requires a fresh flow,
  never an automatic retry of the authorization code.
- Recheck current permission before persisting the resulting grant. Initialize the
  MCP connection and discover tools before reporting connected. Failed replacement
  must leave the previous working connection intact.
- Store access/refresh tokens encrypted with grant revision separate from configuration
  generation. Coordinate refresh across nodes and atomically persist rotated tokens.
  Disconnect revokes local authority immediately; it must not permit a stale refresh
  worker to restore access. Expiry/invalid-grant errors require reconnect, never an
  anonymous fallback or browser prompt during an active call.

Acceptance requires database concurrency/restart tests, local authorization-server
interop, browser return-to-tenant behavior, redaction checks and key rotation across
attempt/registration/grant records. An authorization URL alone proves none of those
lifecycle guarantees. The approved profile is
[MCP 2025-11-25 authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

## Attempt retention and key retirement

Run `mix vxpipe.mcp_oauth.prune --batch-size 100` periodically from a trusted
operator scheduler (for example, every five minutes). Each invocation deletes at
most 500 expired or claimed attempts using row locks with `SKIP LOCKED`; it does
not decrypt payloads and does not touch a live unclaimed attempt. Repeat batches
while `remaining` is nonzero. Zero processed rows with remaining work means rows
may be locked, not that cleanup has completed. Monitor failures and growing
remaining counts. Cleanup is operator-scheduled, not an automatic Console worker.

Output contains only `processed`, `remaining` and `pending_by_key`. The last field
counts live unclaimed attempts by encryption key ID and helps identify keys still
needed by callbacks. First switch all writers to the new key, finish both provider
and saved-MCP credential rotation, then wait for old-key attempts to be claimed or
expire and prune terminal rows. An empty attempt count does not prove rotation of
other stores. Retain old keys while any reader still needs them.

Terminal rows are deleted rather than retained as replay tombstones: absent state
already fails callback lookup, and a claimed attempt's secrets were erased during
claim. The persisted connection/grant owns the subsequent lifecycle. Cleanup shares
row locks with claim, preserving the one-time claim boundary. Independent-node
race testing remains part of the milestone acceptance gate.


The tagged database concurrency lane can be run from `apps/vxpipe_persistence`:

```shell
mix test --include integration test/integration/mcp_oauth_concurrency_test.exs
```

The fixture commits its isolated tenant records, checks out distinct PostgreSQL
sessions for competing operations, asserts different backend PIDs, synchronizes
workers by messages, monitors completion and removes its tenant afterward. It
covers attempt claim exclusivity, pending admission limits, pruning against claim,
refresh claim exclusivity and completion against revocation. These are real
multi-connection transactions within one BEAM node; they do not replace the
separate-node lifecycle and transport acceptance gate.


## Own-client machine grants

The token boundary has a separate client-credentials operation. It accepts
confidential Basic, POST or private-key JWT authentication, requires the discovered
metadata to advertise the grant and selected method, and requires an exact token
endpoint match. Scope syntax is bounded to OAuth scope tokens; fixed grant,
resource and client fields cannot be replaced by arbitrary inputs. It makes one
request through the same pinned HTTPS boundary and redacts token inspection.

This follows [RFC 6749 §4.4](https://www.rfc-editor.org/rfc/rfc6749#section-4.4):
client credentials authenticate the client itself, without a browser callback or
consent redirect. Returned refresh tokens are discarded for this operation;
renewal must use the registered client credentials, not reuse the delegated-user
refresh lifecycle. The adapter's metadata argument must come from trusted backend
discovery/preparation, never browser assertions of server capabilities.

Calls/Console preparation, initialization/tool checks, encrypted registered-client
configuration, durable machine renewal and production forms are implemented.
Authenticated browser and independent-node acceptance remain milestone tasks.
The base MCP authorization profile does not make this grant universally available;
only compatible servers should offer it. See the
[MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

Implemented machine workflow checkpoint: reuse `MCPConnections.connect/update`, its probe
port, permission rechecks and encrypted connection replacement. Only an explicit
Own-client `client_credentials` request may use this path; delegated OAuth still
requires the durable browser-attempt path. Perform fresh metadata validation,
one token grant and MCP initialization/tools before creating/replacing a record.
Persist the selected grant, validated token metadata and private client configuration
together. Reuse durable claim/CAS coordination for renewal, but send a new
client-credentials grant and never request or store a refresh token. Failed or
ambiguous claims remain fenced for explicit reconnection. Discovery can advertise
machine support without pretending a browser grant is available. The preflight
result includes `supported_grants`; machine-only metadata suggests Own-client.

Verification: focused red tests demonstrated all four missing boundaries, then
passed with the existing delegated suites. Three additional local HTTP/database
cases exercise Basic, POST and JWT machine clients through session/CSRF routes,
runtime-triggered renewal, failed/successful replacement and disconnect. No browser
attempt or DCR request is created. Renewal preserves configuration generation and
increments grant revision; replacement increments configuration generation.

The reviewed MCP client-credentials extension targets protocol 2026-07-28.
This milestone retains the
approved 2025-11-25 wire profile and implements the explicitly selected RFC 6749
grant against compatible servers; it does not claim conformance to the newer MCP
extension or switch wire versions. A newer extension/profile adoption is a separate
protocol decision. [Published extension](https://github.com/modelcontextprotocol/ext-auth/blob/main/specification/stable/oauth-client-credentials/2026-07-28/oauth-client-credentials.mdx)

## DCR client-secret expiry

Implemented checkpoint (2026-11-06): retain
`client_secret_expires_at` from managed DCR responses inside encrypted attempt and
grant secrets. RFC 7591 section 3.2.1 requires this integer timestamp when a secret
is issued; zero explicitly means no expiry. Reject missing, malformed or already
expired DCR secrets before browser handoff. Recheck the retained timestamp before
code redemption and refresh, since consent can outlive a short-lived registration.
Never send this internal timestamp as a token-request form parameter.

The token adapter also accepts expiry metadata for confidential client-credentials
requests. Missing expiry in manual/legacy credentials remains unknown, not an
assertion of indefinite lifetime; automatic DCR registration reuse must
require the validated registration metadata. Expiry validation alone does not implement registration reuse or rotation;
reconnect reuse is described below. An expired secret requires reconnect through the
existing failure path; it does not trigger hidden registration during refresh.

Rejected: dropping the expiry after registration, assuming missing DCR expiry means
zero, or automatically retrying token requests with a new registration. Those paths
respectively allow stale secrets, invent provider guarantees, or change the client
identity of an existing grant. See [RFC 7591](https://www.rfc-editor.org/rfc/rfc7591.html#section-3.2.1).

Verification: registration/token tests cover zero, future, missing, malformed and
elapsed expiry; Console tests reject expiry during consent and before refresh
without DNS. Persistence tests retain expiry through encryption and token rotation
and reject attempts to change it through token updates. MCP suite: 96 tests;
Console suite: 450 tests; persistence MCP lane: 29 tests, all passing.

## Reconnect and registration reuse contract

Implemented backend checkpoint (2026-11-06): reuse the connection repository's
existing generation-checked `replace` operation for OAuth reconnect. A tenant
reconnect operation supplies the saved connection ID and expected generation;
Calls must authorize the current browser session before resolving any secrets.
A connected or explicitly retained disconnected connection at the same endpoint
and observed generation is eligible. The pending
attempt records replacement intent alongside its authenticated connection ID and
generation; legacy attempts with no intent remain create-only.

Before token redemption, check that the target still exists at the bound generation.
After fresh token exchange and MCP initialization, recheck installation identity and
current permission, then atomically replace the target at that generation. Preserve
its directory identity. Cancellation, denial, expiry or failed initialization leave
the working grant intact. Replacement, revocation or another reconnect that wins
first makes the old attempt stale; a callback must never resurrect a record revoked
after its attempt was issued. Explicit reconnect of an already retained record is
bound to that record's current revoked generation.
Use the existing encrypted attempt storage and connection replacement transaction,
not a second credential store or network I/O inside a database transaction.

Retain registration provenance privately: selected registration method, issuer,
resource, exact callback, client authentication and validated secret expiry. Fresh
Connect-time discovery still runs. A saved DCR registration may be reused only for
the same issuer/resource/callback and currently supported authentication method,
with validated saved scopes covering all newly selected scopes. Unknown or
insufficient saved scope coverage requires fresh registration. Confidential clients
also require a known unexpired secret. Unsupported, expired,
legacy or mismatched registrations use fresh explicit Connect-time registration.
A supplied initial access token requests fresh DCR. CIMD derives the current
installation metadata identity without registration HTTP. Never reuse an access or
refresh token as registration input, or accept registration credentials from the
browser. This does not create a cross-tenant registration cache.

Rejected: destructive disconnect-before-reconnect, create-on-callback for an
existing connection, guessing legacy registration provenance, or reusing clients
solely because their host names match. Each loses a required lifecycle or identity
boundary. Acceptance must cover canceled/failed replacement, stale generations,
revocation during consent, cross-tenant requests and registration reuse without
registration HTTP. Production custom OAuth forms are enabled; authenticated browser
and separate-node interoperability remain open gates.

The authenticated, CSRF-protected route is
`POST /api/tenants/:tenant_key/mcp-connections/:id/oauth`, with `generation` plus the
usual managed OAuth preparation fields. It returns the same private/no-store
handoff shape as initial Connect and the existing connection ID. Stale generations
return 409; unsupported targets return 422; missing targets return 404. Retained
revoked targets are eligible only through explicit generation-bound reconnect;
revocation after issuance invalidates the older attempt.
The callback uses the encrypted operation binding, never a browser-supplied mode.

Local design review: this depends on T4 generation-checked storage, durable T5
single-use attempts and the secret-expiry checkpoint. The JSON attempt binding
needs no schema migration; old bindings without operation are create-only.
Registration provenance is generated by the protocol adapter and encrypted with
the grant. No separate registration database or cross-tenant cache was introduced.

Verification: Calls tests cover successful replacement, denied consent, stale and
revoked targets, cross-tenant access, authentication changes, and edits during token
exchange. Protocol tests verify fresh discovery plus matching-client reuse without
DCR HTTP, and fresh registration for invalid provenance/expiry or an explicit
initial token. Persistence tests authenticate replacement intent and fence a prior
refresh after replacement. Session/CSRF endpoint tests cover handoff and 409.
Real browser plus HTTP plus database and independent-node acceptance remain open.

## Browser return context

Implemented backend checkpoint (2026-11-06): Console accepts an optional `return_to` for initial Connect and
reconnect. It must be a local path to the same tenant's Integrations root or one
category, with only bounded `q` and `cursor` query fields. Reject absolute/network
URLs, other tenants/routes, fragments, duplicate/unknown query fields and control
characters before protocol preparation. Reconstruct the accepted query instead of
redirecting an unchecked input string. The default is the tenant Integrations root.

Pass the validated location as trusted workflow context, not as an MCP/OAuth
protocol input. Persist it inside the authenticated attempt binding so parallel
tabs, instances and retries retain their own navigation context. On successful
completion, restore that context and add the fixed `mcp=connected` status. Ignore
any return location supplied to the callback itself and revalidate stored context
before redirecting. Legacy attempts without this field return to the root.

The general login return path is broader than this contract and is not reused as
OAuth state. A single session-level "last page" was rejected because simultaneous
flows can overwrite it. Preserved cursors may expire during consent; the existing
directory restart action handles that while retaining the query/category. The
production recovery UI preserves original attempt context across that restart,
including delayed session identity loading. Full authenticated browser acceptance
remains open.

Local design review: Console owns path/query validation; Calls transports the
trusted context and Persistence authenticates it with the rest of the attempt.
The stored field is bounded to 16 KiB, matching the accepted encoded route bound;
search is capped at 200 characters and cursor at 2,048 bytes. No schema migration
or OAuth protocol change is needed. Request diagnostics filter `return_to`.

Verification covers Console validation and callback location, exclusion from
protocol input, Calls start/reconnect propagation, persisted claim restoration,
plaintext-binding tamper rejection and legacy default redirects. The production
OAuth UI supplies its current location and restores a bounded, actor/tenant/attempt-
matched nonsecret draft after failed consent. These backend/component/fixture
checks do not prove the full authenticated browser round trip.

## Local HTTP and database acceptance

The tagged Console `outbound_mcp_oauth_test.exs` and
`outbound_mcp_oauth_renewal_test.exs` compose the production preflight, registration,
authorization, token, initialization, callback, reconnect and renewal paths with the real encrypted PostgreSQL connection/attempt/grant stores. A local
HTTP peer validates authorization code PKCE, exact callback/resource, confidential
client authentication and refresh ownership before returning synthetic credentials.
The actual ExMCP client initializes and lists tools using the resulting bearer token.

Eight browser cases cover managed CIMD, confidential DCR, all four registered-client
authentication methods, registration reuse, replay, failed consent/initialization
and revocation during consent. No
connection exists before callback success, consumed attempts erase ciphertext,
replacement keeps the same ID and increments generation, and failed replacement
preserves the existing grant. Preflight never registers, exchanges tokens or calls
tools. Successful callbacks restore the saved search context.

Own-client cases verify separate authorization/token parameters and additional MCP
headers, encrypted secret/private-key configuration, fresh signed assertions,
successful key/secret replacement and failed initialization preserving the previous
saved configuration. The HTTP peer knows only the registered public key. No DCR
request occurs for a registered client, and read APIs/inspection reveal no keys,
tokens or header values.
The separate `outbound_mcp_oauth_renewal_test.exs` lane has nine renewal/machine cases.
They cover delegated refresh and confidential machine-client acquisition/renewal,
replacement, revocation and scoped failure handling. Machine cases use no refresh
tokens or browser attempts. Both files retain the fixture-identity, loopback and
single-node limitations.

This lane uses a fixture identity backend through the normal session/CSRF routes.
Only test transport adapters reroute validated public URLs to loopback; production
URL policy is unchanged. It does not verify external TLS/DNS, authorization-server
retrieval of the public CIMD document, real browser navigation, or independent BEAM
nodes. Those remain separate acceptance gates. Run from the Console application:
`mix test test/integration/outbound_mcp_oauth_test.exs test/integration/outbound_mcp_oauth_renewal_test.exs --include integration`.

The lane also exposed a busy-result projection bug: immediate Connect after
preflight can legitimately encounter the shared tenant rate limit. Start/reconnect
now preserve that result as HTTP 429 instead of generic 503, with no attempt issued.
Console composition accepts a trusted runner option for isolated tests; production
keeps its default concurrency/frequency/deadline policy. The workflow test runner
uses zero cooldown while retaining bounded task ownership; rate-limit responses
are verified separately. No automatic retry of registration or token requests was
introduced.

## Own-client assertion profile

Decision for T6: reuse ExMCP's `JWT` and `ClientAssertion` primitives for
`private_key_jwt`. It authenticates the registered client during code redemption,
refresh or an explicitly selected client-credentials grant; it is not a new JWT
authorization grant. The authorization server must already know the corresponding
public key. Successful token exchange and MCP initialization remain required
before storing a new connection or replacing a working grant.

Require advertised `private_key_jwt` and signing algorithms. RFC 8414 requires the
signing-algorithm metadata when a JWT client method is advertised and defines no
implicit signing default. Preserve that field during discovery and reject missing
or malformed algorithm metadata. [RFC 8414 §2](https://www.rfc-editor.org/rfc/rfc8414.html#section-2)

The Vxpipe signing profile permits RS256/PS256 with a 2,048–8,192-bit RSA private
key, or ES256 with a P-256 private key. Accept bounded PEM input, not file paths,
public-only keys, shared-secret algorithms or arbitrary claim overrides. Parse
keys into an opaque internal value; only the signed assertion is transmitted.
Each request gets a fresh assertion with a 60-second lifetime and random `jti`;
`iss` and `sub` are the registered client ID and `aud` is the exact token endpoint.
The optional key ID identifies the registered verification key. These are product
profile choices within the client-authentication rules, not universal provider
defaults. [RFC 7523 §§2.2–3](https://www.rfc-editor.org/rfc/rfc7523.html#section-2.2)

Keep an assertion's audience separate from any provider-specific access-token
audience parameter. Reject mixed authentication inputs, client/token-endpoint
mismatches and unsupported algorithms before DNS or token HTTP. Do not silently
fall back to client-secret authentication. Use the existing pinned, bounded,
non-retrying token transport. Each refresh signs again; do not persist reusable
assertions. Persist original key configuration only inside the existing encrypted
grant, and rotate through generation-checked validated replacement.

The assertion/token adapter is now composed into the Own-client authorization-code
backend, including encrypted key storage, refresh and generation-checked reconnect.
Local HTTP/database tests verify registered public keys and replacement. Production
forms are implemented; authenticated browser acceptance remains open. Machine-grant renewal is implemented
through the same durable claim boundary with the separate client-credentials request.
No new cryptography dependency or separate credential store is needed. Local
design review: signing belongs to MCP; encrypted key ownership remains Persistence;
Calls retains tenant authorization and generation checks. Browser field values
cannot supply server-capability assertions or change fixed protocol claims.

Implemented protocol checkpoint: compiled tests verify opaque signing values,
RSA/EC/public/weak-key rejection, exact claims and distinct assertions across code,
refresh and machine grants. Metadata tests reject absent/malformed algorithm lists;
token tests reject mismatched signing identities and inactive credential fields
before DNS. Twenty focused tests, all 107 MCP tests and 13 Console protocol/local
HTTP-database cases pass. Full Own-client workflow acceptance remains pending.

## Own-client literal provider parameters

Implemented protocol checkpoint: authorization and token adapters accept bounded
name/value pairs and a separate optional access-token audience. These are literal
provider values, not expressions or a way to configure the OAuth workflow. The
managed CIMD/DCR preparation input still rejects them. Own-client backend composition
and encrypted persistence plus production forms are implemented. Authenticated
browser and independent-node acceptance remain open.

Allow at most 32 pairs, 64-byte ASCII parameter names, 8 KiB UTF-8 values and
16 KiB total names/values. Audience is at most 2 KiB and cannot also appear in
the generic pairs. Reject controls, duplicate names and all app-owned response,
client, callback, scope, state, PKCE, resource, grant and credential fields.
Also reject `request`, `request_uri`, `response_mode` and `assertion`: these can
introduce another protocol path or move managed fields into a request object.
This is an explicit product boundary; supporting those protocols requires their
own validation, not a generic parameter editor.

Apply the same restrictions to authorization/token endpoint query strings and
reject a supplied parameter that duplicates an endpoint query key. Authorization
parameters go only to the authorization request; token parameters go only to the
selected token grant. Resource remains a fixed separate field. An assertion's
token-endpoint audience is unaffected by provider access-token audience settings.
All token-side validation occurs before transport invocation. No new headers,
redirect behavior, retries or secret logging are introduced.

Verification: 21 focused tests cover bounded values, direct/indirect overrides,
query conflicts and all three token grant bodies; the full 114-test MCP suite and
13 Console protocol/local HTTP-database cases pass. These adapter tests do not
establish the pending Own-client end-to-end lifecycle.

## Own-client configuration composition

Implemented T6 backend contract: keep the browser's registered-client configuration inside the
filtered `credentials` object of an `auth_method: own_client` request. Accept only
the selected grant/client method's active fields. Fresh resource/issuer discovery
supplies server capabilities; browser input cannot assert those capabilities or
select an issuer outside the resource's advertised set. If resource metadata is
absent, an explicitly entered issuer can be discovered separately; do not convert
malformed or conflicting metadata into this fallback.

The protocol configuration boundary validates the registered client ID and either
no secret, a client secret, or the bounded private-key profile. Public clients are
authorization-code only. Delegated grants retain S256 and issuer-response checks;
machine grants require advertised client-credentials support and have no callback
or authorization parameters. Optional endpoint overrides retain the validated
issuer's exact origin and URL/query policy. Missing overrides retain discovered
values. Resource stays bound to the validated MCP endpoint; audience is separate.

Explicit scopes replace discovery prefills for this registered client, subject to
the protocol's bounded scope syntax. Keep authorization pairs, token pairs and
additional MCP headers separate. Validate MCP headers using the existing bearer
configuration boundary so they cannot replace Authorization or transport headers.
They must never accompany discovery or token requests.

Return an opaque configuration containing the authorization context, private token
request and JSON-safe secrets for the existing encrypted store. Store validated
configuration and server-approved signing metadata, not reusable JWT assertions.
The callback/renewal adapters rebuild request authentication from that private
configuration. No separate secret store, arbitrary executable editor, browser
capability flags or implicit registration are introduced.

Authorization-code preparation uses the existing durable attempt, callback,
encrypted grant and reconnect path. Saved additional MCP headers reach both initial
MCP validation and private runtime startup; keys and token parameters never enter
MCP client options. Header validation rejects Authorization collisions before
startup, leaving the runtime token provider as its sole owner. Configuration/grant
errors return specific 422 recovery codes without issuing a browser attempt.

Machine-only authorization metadata may omit an authorization endpoint when its
explicit grant list contains no browser grants. This does not relax S256, code or
issuer-response requirements for delegated authorization. The non-browser
configuration/token adapters, connect orchestration and durable renewal are now
implemented. Own-client production UI is also implemented; authenticated browser
and full milestone acceptance stay open.

Managed CIMD/DCR and Own-client scope defaults now share the challenge-first
selection rule: an explicit challenge scope takes precedence over resource
`scopes_supported`, even when the two sets differ. Own-client explicit scopes can
replace that prefill. A regression test demonstrated managed flows previously
ignored the challenge. [MCP scope selection](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization#scope-selection-strategy)

Design review of this checkpoint: reuse existing Calls authorization and persistence
transactions; add only registered-client protocol composition and private token
projection. Retain old working credentials until a complete new token/initialization
check succeeds. Reject credentials for inactive methods, absent signing metadata,
cross-origin endpoint overrides and provider parameters that alter managed fields.
No UI support is inferred from backend acceptance.
