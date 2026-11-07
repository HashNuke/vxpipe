# Tenant MCP OAuth browser flow

Status: browser start, callback, explicit reconnect, production forms, listed-template
selection and matching nonsecret draft restoration are implemented. Full authenticated
workflow and operational release acceptance remain tracked in
[the integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
The existing Services credential APIs continue to own native providers.

## Ownership and protocol

Console exposes session-only, CSRF-protected tenant POST routes at
`/api/tenants/:tenant/mcp-oauth` and
`/api/tenants/:tenant/mcp-connections/:id/oauth`. Calls checks current tenant write
permission, tenant existence and the installation's public origin/revision. Fresh
protocol preparation performs discovery, registration when required, and S256
request construction; URL-entry discovery remains credentialless and non-mutating.
Only after an encrypted attempt is durable does the response return the
provider authorization URL and opaque attempt/connection IDs.

The shared Console callback at `/oauth/mcp/callback` requires the current browser
session. It rejects ambiguous queries before claiming anything, locates the attempt
using hashed state and bound user/session identity, checks tenant write authority
and the current installation callback, then consumes the attempt once. The
protocol adapter validates the issuer, redeems the code without retry, initializes
the MCP and discovers tools. Calls rechecks installation identity and authority
before saving an initial connection or replacing the observed generation.

The callback is deliberately owned by Console, not ExMCP's local callback listener
or node-local transaction registry. Reuse the existing protocol and encrypted
[storage boundaries](mcp-oauth-storage.md); a second ephemeral replay store would
not protect callbacks routed to another instance. Protocol choices and unsupported
capabilities are recorded in [the protocol decision](mcp-oauth-protocol.md).

## Admission, cancellation and expiry

A dedicated application-supervised completion runner admits at most eight active
callbacks and bounds each composed DNS/token/MCP operation to fifteen seconds.
Its task supervisor and runner restart together, retiring owned work. No tenant
cooldown is applied: preparation and callback are separate operations. Network
requests retain their existing per-request destination, byte and time limits.

Admission follows the authenticated, one-time state claim but precedes DNS and
code redemption. This preserves trusted return context for a busy/timeout result.
The attempt remains consumed; the user starts a fresh authorization flow. Keeping
claimed attempts reusable or retrying an ambiguously redeemed code was rejected.
The completion worker never persists credentials. Calls persists only a successful
result accepted by the runner before its deadline; caller death or a late queued
success cannot save a grant. Access-token expiry is anchored conservatively before
the token request, so subsequent initialization and tools discovery cannot extend it.

## Return context and replacement

The POST may supply a bounded return location within the same tenant's Services
root or category route, with only supported search/cursor fields. Console removes
it from protocol input; storage authenticates it inside the attempt. Successful
callbacks redirect with fixed `mcp=connected` and the bound `mcp_attempt` ID.
After fresh installation/authority checks, claimed failures redirect with fixed
`mcp=denied` or `mcp=failed`. Callback query values never choose the destination,
status or attempt ID. Invalid/unclaimed state and authority/installation failures
remain bare errors. Responses use private/no-store and no-referrer headers.

The production UI submits its current location and restores only a matching,
short-lived nonsecret draft. Backend redirect tests do not establish the rendered
browser round trip; the milestone records authenticated browser evidence separately.
Credentials and provider parameter values are never restored from browser storage.

Explicit reconnect accepts the retained connection ID, exact endpoint and observed
generation, including a disconnected or static-authentication record. It preserves
identity/namespace and directory association; a later edit or revocation fences
the callback. Existing working secrets remain usable until complete replacement
succeeds. Disconnected records need no old secret decryption.

Connected DCR records may reuse registration fields only after fresh issuer,
resource, callback, method, expiry and scope validation. Explicit initial tokens
request fresh registration. Missing/unreadable old encryption keys also fall back
to fresh registration; other repository failures do not. No old access or refresh
token is passed to registration preparation. Initial connection attempts also check
for a retained identity and return an explicit review/reconnect proposal; they do
not silently restore a disconnected connection.

## Verification

Focused tests cover permission and installation changes, CSRF, duplicate query
fields, trusted failure redirects, issuer validation, token lifetime, retained
identity and missing-key replacement. Held DNS/token/MCP checks verify admission,
deadline and caller-death cleanup; an application-runner restart verifies ownership.
A delayed successful callback proves the deadline is checked before PostgreSQL
persistence and the claimed attempt remains consumed.

Eight tagged browser integration cases traverse local OAuth/MCP HTTP, Console
session routes and encrypted PostgreSQL. They cover CIMD, DCR and registered-client
code grants, replay, denial, failed initialization, concurrent revocation, saved
registration reuse, disconnect and restoration. Fixtures route transport to
loopback and provide user identity; these cases do not claim external TLS/CIMD
retrieval, rendered UI, cross-node behavior or runtime refresh acceptance.

Six additional tagged Console cases use two independently supervised BEAM processes
with distinct OS/PostgreSQL identities and a newly created, migrated database per
test. They exercise real persisted identity, installation settings, signed session
cookies and CSRF through the Endpoint pipeline. CIMD/DCR start on one node and
finish on the other; wrong-session/replayed callbacks, remote session/role revocation
and changed installation URLs cannot redeem tokens. Completion also survives
shutdown of the initiating node. The ordinary user's fresh login remains unable
to start OAuth after the tenant-service write grant is removed.
The CIMD/DCR success cases then renew that actual saved grant on the initiating node
and reread it on the callback node: both tokens rotate, grant revision becomes 2,
connection metadata stays unchanged and only one additional token request occurs.

These requests use ConnTest, not a listening Console HTTP server. Local OAuth/MCP
HTTP is real, with validated fixture destinations rerouted to loopback. This lane
does not establish browser/TLS/CIMD retrieval or changes during a held callback.
The combined callback, existing code-grant and runtime-renewal lane passes 25 tests
(seed 593520). See [callback evidence](../../labnotes/20261107-0819-verify-oauth-node-callbacks.md).
