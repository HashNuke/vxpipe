# Current credentials on MCP transport requests

Status: the private credential projection, guarded ExMCP provider and pinned
transport patch are implemented. Saved catalog/compiler and Gateway startup wiring
are described in [saved runtime](saved-mcp-runtime.md). Local active-call acceptance
covers WebRTC and managed incoming/outgoing plus legacy incoming phone admission;
delayed-transfer cases use WebRTC. Independent-node delegated/machine renewal,
transport revocation and caller/runner lifecycle pass controlled HTTP acceptance.
[Browser flows](mcp-browser-acceptance.md) and
[cross-node callback-created grant renewal](../../labnotes/20261107-0819-verify-oauth-node-callbacks.md)
also pass separate lanes. Final local verification passes; external release and user approval remain in
[the integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
This checkpoint depends on the existing
[renewal boundary](mcp-oauth-renewal.md).

## Submission boundary

Calls privately resolves the pinned tenant, connection ID and configuration
generation. Resolution returns current validated request headers after the same
status/generation checks; OAuth also returns its current token. Saved snapshots
contain no bootstrap credentials or keyrings. The MCP runtime
provider accepts this trusted resolver and verifies its result matches the pinned
method. It validates bearer syntax before returning a token. Provider state has an
opaque inspection representation, and no challenge callback starts browser consent
or authorizes an automatic retry.

Owned sessions bind their exact integration PID into the provider for both
initial transport setup and reuse checks. The trusted resolver uses `resolve/5`
for that path; standalone management retains `resolve/4`. There is no fallback
from a session-aware resolution to the management path. Calls forwards the session
through renewal admission and exchange so token/DNS work belongs to the session.
See [participant ownership](participant-mcp-ownership.md) for the lifecycle and
configured pre-admission deadline.

The fixed MCP client profile accepts only this guarded provider. The pinned ExMCP
HTTP implementation otherwise preserves cached credentials when a provider returns
an ordinary error tuple. Vxpipe therefore uses a fixed credential-rejection signal.
The transport patch catches that exact signal on POST and returns a fixed error
before HTTP submission. It never returns the old state as a successful fallback.
This also protects stateless/synchronous HTTP clients from credential-bearing OTP
crash reports. Other exits are not silently swallowed by this correction.

GET/SSE resolves current headers before initial connection and every reconnect.
Credential rejection terminates the SSE process with redacted OTP status instead
of entering the library's ordinary connection retry loop. The SSE client also gives
its most recently observed event ID precedence over the initial HTTP cursor; a
captured header must not move resumption backward. Session DELETE resolves current
credentials through `resolve_cleanup/4`, which cannot renew or wait for renewal.
A still-valid near-expiry token is usable, but expired, refresh-claimed, revoked or
replaced grants skip DELETE. Owned providers without the cleanup callback and
Vxpipe resolvers without that capability fail closed. Local stream cleanup still
finishes; no previous token or ordinary resolver is used as a fallback.

These checks govern subsequent requests. They do not retract an already submitted
request or prove immediate cross-node termination of an existing active stream.

## Clean stream resumption

The HTTP receiver remains attached to the existing SSE process after a clean EOF.
That process owns reconnection, obtains current credentials and resumes from its
latest event ID. Treating its EOF notification as a terminal transport failure
discarded the client's session even when the stream successfully resumed. The
receiver now monitors the SSE process: actual process death unblocks it, including
credential rejection during reconnect. Matching connection notices are consumed
instead of accumulating in the receiver's mailbox; a resumed GET returning 405
returns the existing unsupported-stream result.

This does not retry POST, replay a tool call or initialize another session after a
clean EOF. Disabling SSE or treating every closed HTTP response as terminal was
rejected because either would break session resumption. Explicit client disconnect
performs remote DELETE. Vxpipe session retirement now invokes it under one bounded
grace period before waiting for local descendant termination.

## Session transport ownership

Each `IntegrationSupervisor` now starts a dedicated `DynamicSupervisor` before
its ExMCP client and supplies it through the checked patch's
`:transport_supervisor` option. The supervisor name includes the exact integration
owner PID, and the transport resolves it to that incarnation's PID at connection
time. This option requires a supervisor dedicated to **one client**: disconnect
and transport loss terminate every child, so sharing it between clients is
unsupported. A missing or already-dead supplied supervisor fails closed before
initialization; only local ownership is supported. It does not fall back to
detached workers.

Asynchronous POST workers, standalone SSE workers and their socket tasks, DNS
wrappers, handshake receive tasks and the HTTP receiver run under that supervisor. The client registers and monitors each POST before releasing it
to perform network work; a transport reference rejects stale registration, and
the task reference rejects stale completion. Receiver death also retires the
transport work. Temporary/significant client and worker-supervisor children
retire the integration owner on child loss instead of silently replacing its
client. Explicit disconnect stops these workers before best-effort remote DELETE.

The standalone session API also supplies `:defer_connection`. ExMCP returns from
`init/1` before authorization/network work and establishes the connection in
`handle_continue/2`. For this opt-in supervised HTTP/legacy-profile path, the
client does not trap exits. An owner can therefore terminate it while arbitrary
startup callbacks are blocked. Default dependency startup stays synchronous.
Handshake tasks are monitored instead of linked to this client. A temporary
watcher monitors each helper's requester and deadline independently of that
requester's wait. The nontrapping helper links to its watcher and begins work only
after the caller has installed its monitor and the watcher has acknowledged it.
Requester death, expiry or watcher loss therefore terminates blocked DNS.
The default owned resolver executes directly in this helper, avoiding an additional
linked task outside the supervisor's termination barrier. Custom resolvers remain
responsible for not detaching resources. Helper failures are normalized through the caller's task
monitor. POST, DELETE and initial or
resumed SSE GET pass the exact transport-supervisor PID into that boundary.

A temporary significant lifecycle guard begins before the client. Until validated
readiness is acknowledged, caller/host death or the absolute startup deadline
kills the exact integration. The guard disarms startup monitoring on readiness and stays available to fence
retirement; loss of this child fails closed. This avoids
a second client-binding cleanup mechanism and reliance on `terminate/2` during
forced death.

Loopback tests observe worker termination and peer socket closure after session
close, forced/normal client death, disconnect and receiver death. Separate cases
cover an idle GET stream, stateless HTTP and rejected GET. A dead-supervisor
regression verifies rejected stateless startup. This is a transport
ownership evidence; activation placement and full call-owned renewal teardown
remain in the [ownership milestone](../../labnotes/milestones/participant-owned-mcp-sessions.md).

`close_all/2` fences all selected sessions before concurrent cleanup, with one
absolute grace deadline (1,000 ms by default). Ordinary transport preparation and
final submission after DNS/connect both consult the exact session lifecycle.
Closing permits only one DELETE carrying its cleanup permission. Releasing a
paused request after retirement cannot admit a new POST; denied submission closes
an already-connected socket. Existing admitted work is terminated before close
acknowledges completion. The transport supervisor's DOWN is the local descendant
barrier, including when the client or integration exits first. A shared five-second
observation cap returns an explicit error if that barrier cannot be observed;
it does not grant extra network-cleanup time.

## Pinned patch and build contract

`patches/ex_mcp/runtime-request-credentials.patch` changes the pinned HTTP and SSE
modules plus Client, ConnectionManager, TargetPolicy, bounded HTTP/stream sockets
and default DNS lifecycle handling and status redaction.
Its adjacent manifest records the exact dependency revision and SHA-256
hashes for the patch, original sources and patched sources. `bin/patch-ex-mcp`
accepts the complete original/current state or an explicitly recorded prior
reviewed state through separately checksum-pinned upgrade patches. Unknown modifications,
a different dependency revision, a modified patch or mixed source states fail
without overwriting them. Reapplication verifies the existing patched state.
The upgrade baselines are bounded startup, transport ownership, stream resumption
and the previously supported credential-patch state. Older unrecognized patched
states must be prepared from pristine pinned sources rather than accepted implicitly.

`bin/setup` applies the patch after dependency retrieval and compiles ExMCP for dev
and test with `--include-children`, so a fresh checkout builds prerequisites such
as Plug before compiling the patched dependency. CI uses the same compilation
mode, applies the patch before compilation, includes the patch/manifest in its
dependency cache key and runs the preparation tests. Other clean build/release
pipelines must run `bin/patch-ex-mcp` after `mix deps.get`, then compile ExMCP in
their target environment. This is a release prerequisite. On dependency upgrade,
review the patch and regenerate its manifest deliberately; do not bypass a checksum
failure or silently accept an unreviewed source state.

A narrow tracked patch keeps the existing transport's streaming and destination
limits. Disabling SSE would remove required behavior. A wrapper transport was
rejected because ExMCP client paths depend on the concrete HTTP module/struct.
Broad vendoring adds unrelated ownership. Prefer removing the patch when a reviewed
upstream version provides equivalent submission, privacy and cursor behavior.

## Review and verification

Earlier red tests reproduced skipped provider resolution on DELETE and SSE. Local
HTTP tests verify fresh credentials for initial GET, reconnect and DELETE. New
review regressions reproduced a stale captured resume cursor, cached header leakage
from live SSE termination and custom-header leakage from a live stateless HTTP
client's credential rejection. Supervised startup did not reproduce a leak and
remains unchanged.

The cursor now advances after new stream events while refreshed authorization is
used. SSE status redaction removes both formatted and structured report sentinels.
Stateless HTTP returns a fixed request error with no additional submission and no
header sentinels. Direct rejection tests also assert no DNS or old-token fallback.
Actual loopback interoperability cases are explicitly tagged `integration`.

Patch tests cover clean local-clone application, idempotence, wrong revision,
tampered patches, unknown source changes, mixed source states and upgrade from the
supported reviewed versions, including tampered older upgrade rejection. These
upgrade tests require no repository history. Setup
tests cover preparation/compilation ordering and stopping on patch failure. The
saved-record publication/startup-options/wire slice and local web/phone execution
are now verified.

Eleven Console integration cases run real token requests and ExMCP clients in two
independent BEAM processes sharing committed PostgreSQL records. Rotation on one
node reaches the other's subsequent POST, resumed GET and explicit session DELETE;
another tool succeeds after resumption without initialization. Revocation blocks
all three request methods. Held token responses prove revocation fencing,
per-connection exclusivity with unrelated-tenant progress, and ambiguous-redemption
fencing after a node crash. Machine grants now also cover rotation and revocation
without saving refresh tokens. Caller cancellation and renewal-runner restart
cover both grants, retaining the durable ambiguity fence while permitting fresh
unrelated renewal. Browser/callback acceptance is recorded separately above. Four focused transport
regressions cover clean EOF, terminal credential rejection, repeated
connection notices and resumed GET rejection. See
[checkpoint evidence](../../labnotes/20261107-1017-mcp-runtime-nodes.md) and
[renewal lifecycle evidence](../../labnotes/20261107-1056-mcp-renewal-lifecycle.md).

The full MCP lane passes 184 tests, including the pinned official Everything and
SSE-recovery fixtures. Their npm install/build/start commands run from each
fixture's own checkout so workspace/lock resolution is independent of Vxpipe's
working directory. Fixture revisions and the protocol profile remain unchanged.
