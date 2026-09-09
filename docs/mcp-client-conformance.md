# MCP client conformance profile

Status: partial, pinned evidence for Milestone 10. This document does not claim blanket
MCP client certification.

## Pinned inputs

- Protocol: MCP `2025-11-25`, selected through ExMCP's `:legacy_only` profile.
- Client dependency: ExMCP `1.3.0`, locked by the umbrella.
- Official client harness: `@modelcontextprotocol/conformance@0.1.16`, tag commit
  `21a9a2febd7100d7c17ac1021ee7f2ed9f66a1e0`.
- Additional Everything server fixture: `@modelcontextprotocol/server-everything@2026.8.31`,
  tag commit `a40bc270fb5ece62673f8a1196f57116d885c5eb`, whose lockfile pins MCP SDK
  `1.30.0`.

The harness version is invoked exactly by [the opt-in runner](../bin/test-mcp-conformance);
it is not a runtime application dependency. The runner uses `MIX_ENV=test` only to avoid
starting unrelated development voice-provider configuration. The task itself starts only
`:vxpipe_mcp` and its dependencies.

## Internal public API

- `Vxpipe.MCP.ConnectionKey.new/1` constructs the bounded resolved-integration and
  credential-generation identity.
- `Vxpipe.MCP.Connections.open/3`, `lookup/1`, and `close/1` own production HTTPS session
  lifecycle. `open_loopback_test/3` is a distinct loopback-only fixture entry and cannot be
  selected by a production configuration flag.
- `Vxpipe.MCP.Connection.client/1` gives the internal protocol handle to
  `Vxpipe.MCP.Discovery.discover/2` and `Vxpipe.MCP.Invocation.call/5`.
- Discovery returns a complete `Vxpipe.MCP.Catalog` or an error, never a partial catalog.
  Invocation accepts only a tool in that catalog and validates its arguments before the
  ExMCP request boundary.
- Discovery maps dependency failures to a categorical error rather than returning transport
  diagnostics that could contain authorization data.
- Invocation maps JSON-RPC error objects to `:remote_error`; malformed payloads and mismatched
  response IDs become `:outcome_unknown` after submission. These categories do not include
  remote messages, and the effective wire tests observe exactly one `tools/call` per case.
- The same wire fixture verifies the configured 1 KiB response boundary: content-encoded
  responses are rejected, and oversized chunked JSON and POST SSE responses fail with the
  dependency's incremental `:response_too_large` cause. Vxpipe reports `:outcome_unknown`
  after timeout, disconnect, or these post-submission failures and never resubmits the call.
- `Vxpipe.MCP.ReferenceProbe.run/2` is the fixture-facing boundary that discovers and calls
  Everything's `echo` tool while preserving the remote definition and result as data.

Tenant lookup, credential resolution, enabled-tool selection, agent grants, call lifetime,
and model projection do not belong to this library. The later live-MCP milestone supplies
those inputs.

## Official client scenario matrix

Run date: 2026-09-09. The harness lists these scenarios for MCP `2025-11-25`.

| Scenario | Status | Evidence or boundary |
| --- | --- | --- |
| `initialize` | Pass | 1/1 scored check; exact revision and client metadata accepted. |
| `tools_call` | Pass | 1/1 scored check; initialized, listed `add_numbers`, then invoked it once. |
| `sse-retry` | Upstream defect; corrected fixture passes | Unmodified `0.1.16` negotiates `2025-03-26` despite selecting this scenario for `2025-11-25`, so Vxpipe correctly rejects it. The same pinned source with only that response fixed to `2025-11-25` passes 3/3. |
| `elicitation-sep1034-client-defaults` | Not applicable | Server-requested elicitation is explicitly outside this milestone. |
| `auth/metadata-default` | Not applicable | OAuth onboarding is deferred. |
| `auth/metadata-var1` | Not applicable | OAuth onboarding is deferred. |
| `auth/metadata-var2` | Not applicable | OAuth onboarding is deferred. |
| `auth/metadata-var3` | Not applicable | OAuth onboarding is deferred. |
| `auth/basic-cimd` | Not applicable | OAuth/CIMD onboarding is deferred. |
| `auth/scope-from-www-authenticate` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-from-scopes-supported` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-omitted-when-undefined` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-step-up` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-retry-limit` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/token-endpoint-auth-basic` | Not applicable | OAuth token-endpoint authentication is deferred. |
| `auth/token-endpoint-auth-post` | Not applicable | OAuth token-endpoint authentication is deferred. |
| `auth/token-endpoint-auth-none` | Not applicable | OAuth token-endpoint authentication is deferred. |
| `auth/pre-registration` | Not applicable | OAuth client registration is deferred. |

## Reproduction

From the umbrella root:

```sh
bin/test-mcp-conformance
bin/test-mcp-sse-recovery
bin/test-mcp-everything
```

The harness creates a fresh loopback server per scenario and appends its URL to the Vxpipe
task. The task dispatches the two unmodified official scenarios plus the corrected-fixture
recovery action; any other value fails explicitly. The recovery runner clones exact tag commit `21a9a2f` into a temporary
directory, verifies the commit, applies the committed one-line protocol-version patch, and
runs only `sse-retry`. It removes that temporary checkout afterward. This is an explicit
corrected-fixture result, not an unmodified official pass.

The corrected recovery run observes one `tools/call`, a graceful response-stream close,
reconnection after the server's 500 ms retry value, `Last-Event-ID: event-2`, and delivery
of the original result over the resumed GET stream. It scores 3/3 with no warnings. The
unmodified run is retained as a harness defect because accepting `2025-03-26` would weaken
the product's exact-version gate.

The Everything runner clones and verifies exact tag commit `a40bc270`, installs its locked
dependencies, builds only the Everything workspace, and starts its Streamable HTTP endpoint
on an ephemeral loopback port. Vxpipe negotiates `2025-11-25` with a server-issued session,
discovers the `echo` tool, validates its explicitly declared Draft 7 input schema, invokes it
once, and returns the preserved tool definition and result. No Jido, database, call engine,
or model provider runs in this path.

The earlier date-matched Everything release `2025.11.25` is not a compatible fixture: tag
commit `0155af3` locks MCP SDK `1.19.1`, whose newest supported revision is `2025-06-18`.
Using that package would test fallback negotiation instead of Vxpipe's selected protocol,
so it was inspected and rejected rather than represented as a pass.

## Blocking compatibility findings

ExMCP 1.3.0 and upstream `master` at `56880c6` read HTTP credential trust from the
application-global `:ex_mcp, :security` configuration rather than from each client. A global
union of tenant origins would weaken per-integration credential binding, so production
credentialed remote sessions remain blocked until this is resolved through a public
dependency boundary. The loopback conformance successes carry no credentialed-production
claim.

Two further release-level gaps were reproduced against the public client path:

- A corrected pinned recovery fixture sent 300 complete progress events totaling 339,790
  bytes of decoded JSON after `Last-Event-ID` reconnection. The invocation succeeded with
  both `max_response_bytes` and `max_stream_buffer_bytes` set to 262,144 bytes. ExMCP bounds
  an incomplete SSE frame, then clears that buffer after each complete event; it does not
  retain a cumulative response-stream counter across events or reconnections.
- ExMCP's asynchronous POST and transport failure handlers interpolate the raw failure term
  into log messages. Decode failures can contain the malformed response body, so Vxpipe
  cannot establish the stronger credential-free diagnostic contract at the public wrapper
  boundary alone.

The recovery deadline itself behaves correctly: with Vxpipe's 5,000 ms invocation deadline
and a server-provided `retry: 6000`, the submitted call returned the bounded
`:outcome_unknown` result at the original deadline and did not reconnect or resubmit the
tool. The cumulative byte half of that acceptance gate remains failed.

Vxpipe will not work around these gaps by sharing a global union of tenant trust, installing
a host-wide Logger filter, disabling the required SSE path, or introducing a second MCP
transport/parser. Milestone completion requires an ExMCP release or explicitly maintained
dependency revision that exposes per-client trust, sanitized diagnostics, and cumulative
stream accounting through its supported boundary.

As of the 2026-09-09 follow-up, the upstream repository has no issue, pull request, or branch
covering these findings, and `master` contains only unrelated test changes after the 1.3.0
release. A temporary TDD patch demonstrated that per-client trust and the primary client-log
sanitization are small changes: the focused upstream suites passed 14 and 33 tests,
respectively. That patch was not adopted or published.

Cumulative accounting requires a deliberate dependency API rather than a counter added to
the SSE process. MCP `2025-11-25` can multiplex several pending requests over one legacy GET
stream, and that process survives reconnects. A transport-lifetime counter would therefore
combine unrelated calls and eventually fail a valid later invocation. Correct accounting
must associate complete response events with their JSON-RPC request IDs and progress events
with request-scoped progress tokens, retain those budgets across reconnects, and close the
affected work when its budget is exhausted.
