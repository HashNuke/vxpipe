# Current credentials on MCP transport requests

Status: the private credential projection, guarded ExMCP provider and pinned
transport patch are implemented. Saved catalog/compiler and Gateway startup wiring
are described in [saved runtime](saved-mcp-runtime.md). Full per-route active call
acceptance and independent-node revocation remain open in
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
credentials too. A revoked connection skips remote DELETE while allowing local
stream cleanup to finish.

These checks govern subsequent requests. They do not retract an already submitted
request or prove immediate cross-node termination of an existing active stream.

## Pinned patch and build contract

`patches/ex_mcp/runtime-request-credentials.patch` changes the pinned HTTP and SSE
modules plus Client status redaction. Its adjacent manifest records the exact dependency revision and SHA-256
hashes for the patch, original sources and patched sources. `bin/patch-ex-mcp`
accepts the complete original/current state or the exact previous reviewed state
through a separately checksum-pinned upgrade patch. Unknown modifications,
a different dependency revision, a modified patch or mixed source states fail
without overwriting them. Reapplication verifies the existing patched state.

`bin/setup` applies the patch after dependency retrieval and compiles ExMCP for dev
and test. CI applies it before compilation, includes the patch/manifest in its
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
previous reviewed version. The upgrade test requires no repository history. Setup
tests cover preparation/compilation ordering and stopping on patch failure. The
saved-record publication/startup-options/wire slice is now verified; full
per-admission room/transfer and independent-node acceptance gates remain open.

The full MCP lane passes 179 tests, including the pinned official Everything and
SSE-recovery fixtures. Their npm install/build/start commands run from each
fixture's own checkout so workspace/lock resolution is independent of Vxpipe's
working directory. Fixture revisions and the protocol profile remain unchanged.
