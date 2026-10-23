# Platform MCP server acceptance

This opt-in runner exercises the production MCP HTTP boundary with the official
TypeScript client. It complements the normal endpoint and persisted-OAuth tests;
the outbound checks in `bin/test-mcp-conformance` establish a different contract.

## Run locally

Run `bin/setup` first. The runner uses the checkout's test build and Node/npm.
The checkout's isolated PostgreSQL test database must be available. Run this lane
serially with database tests: its shared SQL sandbox owns one transaction for the
fixture lifetime. It never loads live-provider credentials, calls carriers or
voice providers, or installs packages during acceptance.

Cache the exact acceptance tools once, if they are not already present:

```sh
npm exec --yes \
  --package=@modelcontextprotocol/conformance@0.1.16 \
  --package=@modelcontextprotocol/sdk@1.30.0 \
  -- node --version
```

Then run from the checkout:

```sh
bin/test-platform-mcp
```

The runner compiles the test build, finds those exact package versions in npm's
execution cache, and fails with setup instructions if either is missing. It does
not install packages during acceptance. There is no additional frontend package
or runtime dependency. The protocol profile is `2025-11-25`; the dependency
revision is the checkout's committed `mix.lock`.

## Boundaries exercised

Each fixture runs in a separate BEAM process with loopback-only Bandit listeners
on dynamically allocated ports:

- `Vxpipe.Gateway.HTTP.Endpoint` at `/mcp`.
- `Vxpipe.Gateway.HTTP.Mount` at `/embedded/mcp`.
- The actual `Vxpipe.Console.Endpoint` and its configured Gateway mount at `/mcp`.

The fixture starts the actual Console application and its Gateway, Calls, Identity
and Persistence dependencies. It configures real repository implementations,
bootstraps synthetic users, roles and sessions inside the SQL sandbox, and issues
real Boruta authorization codes and OAuth tokens for each listener's exact resource.
Separate Settings API keys verify unchanged product HTTP authentication and key
rejection at MCP. It uses production policy, storage and projection code. Grant
revocation reaches the real store; fixture shutdown rolls back all writes.
The native HTTP listener and managed-cleanup reconciler are disabled so only the
three isolated listeners serve requests and no background reconciliation scans
escape the fixture. Existing endpoint tests separately cover normal runtime
configuration and active-call cleanup.

The pinned official SDK performs the handshake, discovery and all 17 tool calls
on each mount:

- Tenant listing and detail, with bounded pagination.
- Spec creation, complete source update, explicit revision publication,
  historical retrieval and listing; provider and model discovery.
- Call creation with declared variables, idempotent replay, default-participant
  join-token issuance, prepared-call hangup and terminal replay.
- Safe role options, user creation, disabling, partial update preserving omitted
  fields, reactivation and filtered listing.

Each mount also checks scoped call/spec/administrator catalogs of 5/12/17 tools, own-tenant
scope and concealed foreign lookup, denial of account tools to tenant-only users,
page-size bounds and unknown or wrongly typed arguments. It checks matching
structured/text results and exclusion of password, credential, resolved-plan and
digest fields. Join-token issuance intentionally returns its token; subsequent
outputs must not repeat that secret. Missing/invalid credentials, a different
valid grant using the session, real revocation after initialization and session
DELETE all reject continued access.

These are prepared calls only: no token redemption, media, provider invocation or
active runtime teardown occurs. Active hangup, exact-incarnation ownership,
carrier cleanup and request-owner death remain separate owning integration tests.
The SDK lane does not claim TCP-disconnect cancellation coverage.

The SDK closes its client transport separately from `terminateSession()`, so
restart coverage preserves an existing session before stopping the server.

## OAuth acceptance

Each mount checks real HTTP protected-resource/authorization-server discovery,
public-client DCR, S256 exchange (wrong verifier first), refresh continuation of an
existing MCP session, cross-resource rejection and token revocation. Raw HTTP API
keys are rejected at MCP, while the product HTTP API still accepts them.

The Console mount performs the full HTTP browser flow: initial authorization,
opaque resume path, login redirect, CSRF-authenticated login, consent render,
CSRF approval, validated callback, and code exchange. Gateway and embedded Plug
fixtures use a private authenticated fixture command for consent because those
Plugs do not own browser pages; their discovery and credential endpoints still
use actual HTTP. Rendered Chrome desktop/mobile checks complement the scripted
flow; their evidence is recorded in the OAuth milestone.

## Expiry and restart

After the mount checks, the complete fixture BEAM exits. Its replacement binds
the same Gateway port with fresh sandbox credentials. The fixture first verifies
that the old ID is absent through the public SessionManager lookup, then checks
HTTP 404 using a fresh valid OAuth token. Fresh initialization must succeed. This proves
loss of in-memory sessions across process restart independently of grant binding.

For accelerated idle expiry, only the replacement fixture uses a one-second
TTL and 25 ms cleanup interval. Before serving requests, it replaces its own
SessionManager child through public Supervisor operations and the dependency's
documented `start_link/1` options. It never modifies another VM or the normal test
suite's SessionManager, private state, or clock.

The fixture waits up to five seconds for `get_session/1` to report termination.
This read does not refresh activity. The client then verifies HTTP 404 for the
expired session and a successful tenant call with a new session. This establishes
expiry mechanics with accelerated timing, not a measured production TTL. Current
dependency defaults are 3,600 seconds idle TTL and a 60-second cleanup interval;
cleanup can therefore lag the idle threshold.

## Official conformance evidence

The pinned CLI has no custom-header option. A temporary loopback proxy adds the
synthetic Bearer header and forwards request/response bodies unchanged to the real
Gateway endpoint. Direct SDK tests above exercise authentication without that
proxy. The proxy is solely a harness adapter; it is not deployed.

| Scenario | Coverage |
| --- | --- |
| `server-initialize` | Unmodified official scenario through the header proxy |
| `ping` | Unmodified official scenario through the header proxy |
| `tools-list` | Unmodified official scenario through the header proxy |
| `tools-call-*` | Omitted: require special `test_*` tools; all 17 product tools are checked with the SDK |
| Resources, prompts, logging, completion, elicitation, SSE | Omitted: outside the enabled product profile |
| DNS rebinding | Omitted: scenario targets unauthenticated localhost servers; normal endpoint tests cover Host/Origin policy |
| OAuth | Focused discovery, DCR, browser consent, PKCE, rotation and revocation flow above; not blanket conformance certification |

See the official [conformance integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md).
These are selected interoperability checks, not blanket MCP or OAuth certification.

## Evidence and cleanup

Verified locally on 2026-10-16: all 17 tools passed on each of the three mounts,
including OAuth discovery/exchange, scoped catalogs, refresh continuity and
persisted revocation. The Console browser flow passed with the native form
`Origin: null` header and CSRF protection. The three selected official
scenarios, whole-BEAM restart, accelerated expiry and fresh-session recovery also
passed.

The runner emits one concise `PASS` line per group and exits nonzero on failure.
Failures identify the operation or fixture stage without printing private
transcripts. Credentials, passwords and issued join tokens travel only through
private local pipes or requests; they are never emitted in runner output. It
bounds startup, commands and conformance subprocesses, terminates remaining
children on failure, and removes temporary harness results. Sandbox shutdown
rolls back fixture data even when the BEAM connection is killed.

The scripts live under `verification/platform_mcp/` and are not discovered by
`mix test`. Record each run's outcome and dependency revision in the milestone
and checkpoint labnotes. These checks complement the normal persisted authority,
CSRF, concurrency and lifecycle regression suites rather than replacing them.

## Active-call lifecycle acceptance

The separate local integration lane exercises canonical call creation and token
issuance, actual managed admission, Session issuance, a connected local WebRTC
peer, authorized HTTP hangup, and durable archive/cleanup completion:

```sh
cd apps/vxpipe_console
mix test --only integration test/integration/managed_web_hangup_test.exs
```

It uses the isolated PostgreSQL database, human web participants and a local peer
with no STUN servers or external providers. Process monitors prove Session,
WebRTC root and tracker termination before checking the durable `ended` projection.
A second case deliberately loses the tracker and proves that exact shutdown and
recovery retain unknown cleanup instead of fabricating completion. Both cases
passed locally. Carrier and transactional race coverage remains in its owning
Gateway and Persistence suites; this web lane does not substitute for those tests.

## Request bounds and sensitive failures

Gateway's normal MCP tests cover malformed/oversized requests, concurrent admission,
request-owner death and callback deadlines. The sensitive-failure tests exercise
password-bearing account creation faults/timeouts and generated join-token storage
faults, capturing diagnostic logs as well as responses. Successful token issuance
still returns its token to the authorized caller.

A separate real loopback HTTP check verifies a stalled authenticated request body
holds admission capacity, times out, terminates its request process and releases
capacity for the next request:

```sh
cd apps/vxpipe_gateway
mix test --include integration test/integration/mcp_slow_body_test.exs \
  test/vxpipe/gateway/mcp/sensitive_failures_test.exs
```

All three tests passed locally. The accelerated body deadline verifies application
behavior; incomplete HTTP headers remain bounded by the HTTP server's own socket
configuration. This evidence does not claim TCP-disconnect cancellation or universal
secret-leak detection outside the exercised authentication/tool failure paths.
