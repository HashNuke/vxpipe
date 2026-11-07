# Tenant MCP machine grants and renewal

Status: backend machine acquisition, saved-grant renewal, credentialless OAuth
catalog refresh, production forms and saved-connection runtime wiring are implemented.
Independent-node token/transport and authenticated browser acceptance remain open in
[the integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
These operations extend existing tenant MCP management and encrypted grant storage;
native providers continue using the Services APIs.

## Machine acquisition

The existing session-authorized MCP create/replace routes accept `own_client`
with an explicit `client_credentials` grant and a bounded draft revision. Console
performs fresh resource/issuer discovery and registered-client validation, obtains
a token and initializes the MCP/tools under the bounded preflight runner. Calls
rechecks current authority before saving. A failed replacement preserves working
credentials; generation fencing prevents concurrent edits from being overwritten.

Only supported confidential client methods are accepted: Basic, POST secret or the
validated private-key JWT profile. Require advertised client-credentials support.
There is no consent redirect, browser attempt, callback or refresh-token grant.
Store validated client configuration and necessary server metadata encrypted;
discard any refresh token returned by the machine token endpoint. Additional MCP
headers accompany initialization, never discovery or token HTTP. Provider parameters
cannot replace fixed grant/resource/authentication fields.

## Renewal ownership and admission

Calls owns the trusted renewal coordinator. Its caller must already have authority
to use the tenant connection; it is not a public management API. The existing
repository port owns durable claim/complete/fail operations. Console's refresh
protocol port has two operations: `run(options, tenant, operation)` for bounded
admission and `refresh(options, claim)` for one token request. This keeps Calls
independent of the MCP protocol application while admitting before database claim.
Production repository identity is passed explicitly in repository options.

A dedicated application supervisor couples the renewal runner with its task
supervisor. Each Console/MCP application instance admits up to eight concurrent
renewals across connections, with a fifteen-second claim/exchange budget and no
tenant cooldown. Per-connection database claims remain authoritative across
instances. A busy pool creates no claim and leaves the grant/revision unchanged.

The worker returns a tagged claim failure or claimed exchange result. Only a result
accepted by the runner before its deadline reaches Calls' complete/fail stage.
Persistence remains outside the worker and retains the store's independent claim
deadline, connection generation and grant-revision checks. A caller delayed after
admission cannot bypass those final checks. Per-request HTTPS, DNS, destination,
request/response size and time limits remain enforced by the existing token adapter.

Successful renewal rotates encrypted tokens atomically, retaining omitted refresh
tokens/scopes under the storage contract and clearing an omitted access-token expiry.
Machine renewal uses its saved client-credentials grant and validated metadata;
delegated renewal uses the saved refresh token. Build a fresh client assertion for
each request when using private-key JWT. Anchor access-token expiry before HTTP,
including initial machine acquisition, so request/MCP-check duration cannot extend it.

## Failure and runtime boundaries

Do not retry an ambiguously redeemed refresh token. Protocol failure fences the
claim for reconnect. Timeout, caller death or runner restart after claim may discard
a successfully rotated response; the durable claim remains fenced rather than
falling back to the old token or permitting another redemption. Until its deadline
it reports renewal in progress; afterward reconnect is required. Background
continuation was rejected in favor of this explicit caller-owned lifecycle.

The private resolver verifies tenant, ID, connected status and configuration
generation on every read. It renews once near expiry, rereads persisted state, and
returns only the access token for OAuth. Active/expired ambiguity claims take
precedence over a seemingly unexpired saved token. Static methods continue using
their existing private credential projection. This resolver alone does not complete
the later transport/compiler wiring.

Authorized `refresh_tools` management reuses current OAuth credentials and saved
MCP headers. The catalog write preserves current credentials and configuration
generation; a necessary token renewal can advance the grant revision. The operation
reuses existing authorization and generation checks; no
credential values return to the browser.

## Verification and limits

Two controlled-clock regressions and four admission/deadline regressions failed
before the fixes. Held injected token requests verify zero-capacity rejection,
cross-tenant saturation before claim, caller-death/timeout cancellation and queued
late-success rejection before PostgreSQL persistence. These prove orchestration
ownership, not physical token-socket closure. Production token HTTP continues to
use the existing synchronous SecureHTTP socket and linked DNS boundary.

Nine tagged local HTTP/database cases cover machine Basic/POST/JWT acquisition,
renewal and replacement plus delegated CIMD/DCR/registered-client renewal and tools
refresh. Five additional real-store boundary cases exercise cancellation/admission.
Registered application-runner restart coverage verifies retirement of its tasks and
nested work, then successful fresh admission. Public projections and stored envelopes
exclude plaintext secrets. The fixtures use local transport routing and a fixture
identity backend; external-provider and independent-node token/transport acceptance
remain open.

Seven persistence cases run public repository operations in separate BEAM processes
against the same committed PostgreSQL database, asserting distinct OS and database
backend IDs. They cover attempt claim/prune/cap races, refresh exclusivity and
completion versus revocation, plus a held claim revoked by another node and abrupt
claimant termination. The surviving node cannot reclaim the ambiguous grant or
complete it at the claim deadline. Database fencing passes without changing the
saved credentials; this does not yet prove cross-node token-socket or MCP transport
lifecycle behavior. See [evidence](../../labnotes/20261107-0959-mcp-cross-node.md).
