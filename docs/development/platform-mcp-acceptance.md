# Platform MCP server acceptance

This opt-in runner exercises the production MCP HTTP boundary with the official
TypeScript client. It complements the normal endpoint and persisted-key tests;
the outbound checks in `bin/test-mcp-conformance` establish a different contract.

## Run locally

Run `bin/setup` first. The runner uses the checkout's test build and Node/npm.
It never loads live-provider credentials or starts a database, carrier adapter,
voice provider, or the umbrella application tree.

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

The fixture starts the required library applications and its own supervised
listeners, Console endpoint, admission process and synthetic credential state.
The Console application tree is not started. Authentication and tenant storage
use the existing explicit adapter ports; the production authentication parser,
MCP handler, Calls authorization, projections and ExMCP HTTP implementation run
unchanged. Fixture credentials are deliberately public test strings. Revocation
is simulated by changing the credential adapter's result; persisted revocation
is covered separately by Console's normal endpoint tests.

The pinned official SDK performs the handshake, discovery and real tenant tool
calls. Each mount checks:

- Negotiated protocol and server-issued session ID.
- Scoped tenant listing and detail, matching structured/text results, and concealed
  foreign-tenant lookup.
- Rejection of invalid tool arguments.
- Missing/invalid credentials, a different valid key using the session, and a key
  revoked after initialization.
- Session DELETE followed by rejection of the obsolete session ID.

The SDK closes its client transport separately from `terminateSession()`, so
restart coverage preserves an existing session before stopping the server.

## Expiry and restart

After the mount checks, the complete fixture BEAM exits. Its replacement binds
the same Gateway port. The old session must return HTTP 404; fresh initialization
must succeed. This proves loss of in-memory sessions across process restart.

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
| `tools-call-*` | Omitted: require special `test_*` tools; actual tenant tools are checked with the SDK |
| Resources, prompts, logging, completion, elicitation, SSE | Omitted: outside the enabled product profile |
| DNS rebinding | Omitted: scenario targets unauthenticated localhost servers; normal endpoint tests cover Host/Origin policy |
| OAuth | Not implemented or claimed; authentication uses static Bearer headers |

See the official [conformance integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md).
These are selected interoperability checks, not blanket MCP or OAuth certification.

## Evidence and cleanup

Verified locally on 2026-10-15: all three SDK mount checks, all three selected
official scenarios, whole-BEAM restart, accelerated expiry and fresh-session
recovery passed. The runner emits one concise `PASS` line per group and exits
nonzero on failure. It bounds startup, commands and conformance subprocesses,
terminates remaining children on failure, and removes temporary harness results.
Raw transcripts and session IDs are not committed. Update the milestone and
checkpoint labnotes with each relevant run's outcome and dependency revision.

The scripts live under `verification/platform_mcp/` and are not discovered by
`mix test`. They currently exercise read-only tenant tools, not the milestone's
later call-spec, call-control or user-management capability matrix. Request-owner
death and admission cleanup have separate focused Gateway tests; this runner does
not claim TCP disconnect cancellation coverage.
