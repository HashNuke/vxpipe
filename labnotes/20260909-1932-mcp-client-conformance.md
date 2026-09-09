# MCP client conformance

## 2026-09-09 — isolated milestone checkpoint

- Started the implementation on `milestone/mcp-client-conformance` from the clean
  milestone-9 mainline. Milestone work will remain on this branch and land as small,
  coherent commits before the branch is merged.
- Confirmed that ExMCP 1.3.0 is the current released package and downloaded the
  published Hex source for boundary review. No dependency or runtime code has been
  added yet.
- Reviewed the released HTTP transport, bounded HTTP client/stream, target policy,
  client connection lifecycle, request path, tool operations, schema policy, and
  package dependencies. This was a source-level compatibility check, not a claim of
  conformance.

## Confirmed dependency behavior

- The explicit client profile can request legacy-only MCP `2025-11-25`. Vxpipe must
  additionally inspect the negotiated client status and reject any other revision.
- Each HTTP request resolves the complete DNS answer, rejects mixed or disallowed
  addresses, pins the selected address for the connection, preserves the hostname for
  TLS verification, removes caller-supplied Host headers, requests identity encoding,
  and applies incremental request/response byte limits.
- HTTPS verifies peer certificates and hostnames by default with TLS 1.2 or 1.3.
  Plain HTTP remains supported by the dependency, so the production Vxpipe config
  boundary must reject it. A separately constructed loopback test profile may allow
  HTTP for conformance fixtures.
- The bounded request path does not follow redirects. Compressed responses are
  rejected rather than decompressed outside the byte budget.
- Unexpected connection loss fails pending requests before ExMCP reconnects and
  performs a new handshake. It does not automatically submit those pending requests
  after reconnecting.
- `tools/list` accepts a cursor but returns one page. Whole-operation page, cursor,
  aggregate-byte, and deadline limits therefore belong in the Vxpipe discovery
  wrapper.
- ExMCP exposes a bounded schema policy that rejects cross-document references by
  default and describes JSON Schema 2020-12 validation. The effective outgoing
  argument path still needs a project-owned pre-submission contract test.

## Public-boundary decisions for implementation

- Use `ExMCP.Client.make_request/5` for `tools/call`, with explicit
  `retry_policy: false`, `http_stream_retry: :safe_only`, and
  `max_mrtr_rounds: 0`. The higher-level `call_tool` helper can refresh headers and
  submit the invocation again after a protocol header mismatch, while the default
  modern stream mode is at-least-once. Neither behavior matches Vxpipe's
  no-speculative-resubmission contract.
- Keep ExMCP reconnection enabled for session recovery, but map a submitted request
  interrupted before a trustworthy response to an unknown outcome. Callers may make
  a new explicit invocation after readiness returns; Vxpipe will not replay the old
  one.
- Apply one absolute deadline and aggregate decoded-byte budget in the Vxpipe wrapper
  across every discovery page. ExMCP's limits remain the per-response transport
  defense.
- Keep endpoint names, remote tool names, schemas, cursors, and credentials as data;
  no value from a remote catalog becomes an atom or module.

## Compatibility gap to resolve before production transport work

ExMCP's HTTP transport reads trusted origins from application-global `:ex_mcp`
security configuration. Its public client options do not currently pass a per-client
trusted-origin set into the transport security guard. That is awkward for independently
configured application and tenant integrations and must be resolved at the dependency's
public boundary without weakening credential-origin binding. Loopback tests are not
evidence that this production concern is solved.

## 2026-09-09 — pinned dependency and client profile

- Added the `vxpipe_mcp` umbrella child with direct, exact `ex_mcp == 1.3.0`
  ownership and a direct JSV dependency for the forthcoming outgoing-argument
  validation boundary. The child has no Jido, call-engine, database, gateway, or
  Console dependency.
- Red: the focused client-profile test first failed because `ClientOptions.build/1`
  did not exist. A second test then demonstrated that an HTTP remote endpoint was
  incorrectly accepted.
- Green: `ClientOptions` now pins HTTP transport mechanics to the legacy-only
  `2025-11-25` revision, keeps generic retry disabled, enables reconnect without
  replay, and rejects plaintext production endpoints.
- Verification: the focused child suite passes with 2 tests and 0 failures. Root
  formatting, warnings-as-errors compilation, strict Credo (280 files, no issues),
  and unused-dependency checks pass.
- A root `mix test` attempt reached the existing PostgreSQL setup alias and could not
  authenticate against the local server. No database is required by this child; the
  focused test was rerun from its owning application. The complete umbrella suite will
  use the established isolated PostgreSQL setup at the milestone completion gate.

## 2026-09-09 — bounded catalog discovery

- Red: three focused tests failed at compile time because the discovery/catalog boundary
  did not exist. They define multi-page cursor propagation, complete raw-definition
  preservation, repeated-cursor rejection, and aggregate decoded-size rejection.
- Green: added a narrow protocol-client behaviour, an ExMCP-only implementation, a bounded
  pagination coordinator, and an immutable catalog index. These responsibilities remain in
  separate modules; tenant selection, connection ownership, invocation, and model exposure
  are not mixed into discovery.
- Discovery carries one decreasing timeout across all pages, disables generic retries at
  each ExMCP request, allows only safe read-stream recovery, rejects repeated cursors, and
  withholds the entire catalog when any page fails or exceeds its aggregate re-encoded JSON
  byte budget. Tool definitions remain complete string-keyed maps; none of their names or
  schema values become atoms or modules.
- Added Jason as a direct dependency because Vxpipe itself measures the stable encoded size
  of decoded page data instead of depending transitively on ExMCP's JSON dependency.
- Verification: `mix test` and warnings-as-errors compilation pass in `vxpipe_mcp` with
  5 tests and 0 failures. `mix deps.unlock --check-unused` passes from the umbrella root.
  Root `mix credo --strict` checks 284 source files with no issues. A child-local Credo
  command is unavailable because Credo is an umbrella-root development dependency.
- This checkpoint does not prove an actual ExMCP connection, initialization, negotiated
  version, server-issued session, invocation, or conformance scenario. Those boxes remain
  open.

## 2026-09-09 — validated invocation boundary

- Red: three focused invocation tests failed because `Vxpipe.MCP.Invocation` did not exist.
  They require invalid arguments, unknown tools, and cross-document schema references to
  stop before the protocol boundary; a valid call must preserve its data and timeout; an
  oversized decoded result must not be returned.
- Green: added `ArgumentValidator` for the JSON Schema concern and `Invocation` for catalog
  selection, deadline, submission, and result-budget coordination. This keeps schema
  mechanics out of the transport adapter and catalog modules.
- JSV builds untrusted schemas with no remote resolver, atom-based casts disabled, and the
  2020-12 dialect fixed. Runtime validation uses `cast: false`, so validation cannot silently
  coerce model arguments before a tool call.
- The ExMCP adapter submits `tools/call` through `make_request/5` with `retry_policy: false`,
  `http_stream_retry: :safe_only`, and zero MRTR rounds. It exposes only categorical
  not-submitted, remote-error, or unknown-outcome failures; dependency error payloads are
  not returned through the Vxpipe invocation API.
- Verification: the complete `vxpipe_mcp` suite passes with 8 tests and 0 failures;
  warnings-as-errors compilation, root formatting, strict Credo over 286 source files, and
  the unused-lock check pass.
- This deterministic checkpoint does not yet prove transport-level incremental response
  limits, initialization/readiness, or a real remote invocation. Those remain open.

## 2026-09-09 — scoped supervised connections

- Red: three focused lifecycle tests failed because connection identities, handles, and
  supervised ownership did not exist. They require reuse for one integration/credential
  generation, isolation across generations, credential-free handles, complete subtree
  retirement, and rejection/cleanup of a mismatched negotiated revision.
- Green: the application now supervises an explicitly named unique Registry and
  `DynamicSupervisor`. Each dynamic integration subtree owns exactly one protocol client;
  no worker starts another worker directly. `Connections` coordinates open/reuse/close,
  while key validation, registry naming, connection data, runtime adaptation, and subtree
  supervision remain separate cohesive modules.
- A connection key contains only bounded integration and credential-generation strings.
  Endpoint headers stay in the supervised client options and never enter the returned
  connection handle or readiness error. Reusing the same key intentionally pins the
  existing session; the integration owner must change the generation when credentials do.
- Readiness requires both `connection_status: :ready` and exact MCP `2025-11-25`.
  Mismatched or unready trees are terminated before `open/3` returns an error.
- Verification: the complete `vxpipe_mcp` suite passes with 11 tests and 0 failures;
  warnings-as-errors compilation, root formatting, strict Credo over 293 source files, and
  the unused-lock check pass.
- Tests use a deterministic supervised runtime double. Actual ExMCP initialization,
  session headers, connection loss/recovery, and reference-server use remain unproven.

## 2026-09-09 — explicit transport profiles and limits

- Rechecked ExMCP upstream `master` at commit `56880c6` after inspecting release 1.3.0.
  Its HTTP request guard still reads application-global trusted origins; there is no newer
  released or upstream per-client option to pin. A global union of tenant origins is not an
  acceptable substitute for per-integration credential binding, so this compatibility gate
  remains open.
- Red: the focused profile tests showed that transport limits were absent and the dedicated
  loopback test builder did not exist.
- Green: `TransportOptions` now owns validated positive limits. Production client options
  explicitly bound request bodies, responses, streaming buffers, DNS resolution, connection,
  and request duration instead of inheriting broad dependency defaults. Private-host
  exceptions remain explicit data passed to ExMCP's connect-time/DNS-rebinding policy.
- `ClientOptions.build/1` remains HTTPS-only and rejects userinfo/fragments. A `test_mode`
  key cannot weaken it. `build_loopback_test/1` is a separate code path that accepts only
  plaintext localhost, IPv4 loopback, or IPv6 loopback targets and disables reconnect for
  deterministic fixtures.
- Verification: the complete `vxpipe_mcp` suite passes with 13 tests and 0 failures;
  warnings-as-errors compilation, root formatting, strict Credo over 294 source files, and
  the unused-lock check pass.

## 2026-09-09 — official initialization and tool-call scenarios

- Pinned the official legacy client harness to
  `@modelcontextprotocol/conformance@0.1.16` / tag commit `21a9a2f` and the additional
  Everything fixture to `@modelcontextprotocol/server-everything@2025.11.25` / tag commit
  `0155af3`. The latter is recorded but not yet claimed as executed.
- Red: the first official `initialize` run failed because the Vxpipe conformance task did
  not exist. After adding it, the next run exposed that umbrella development runtime config
  required an unrelated Deepgram key. The driver now starts only `:vxpipe_mcp`; the pinned
  harness invokes it under `MIX_ENV=test`, where unrelated voice apps/config are not loaded.
- Added `Connections.open_loopback_test/3` as a distinct fixture-only entry. A focused test
  first proved that it was missing and that ordinary `open/3` still rejects the same HTTP
  endpoint. A transient post-shutdown Registry entry also surfaced; lookup now refuses a
  dead registered PID, and retirement is acknowledged with process monitors.
- Green: official `initialize` passes 1/1. Official `tools_call` passes 1/1 after observing
  `initialize`, `notifications/initialized`, `tools/list`, and exactly one `tools/call` for
  the discovered `add_numbers` schema. No Jido, database, call engine, or model provider is
  started by the task.
- Added `bin/test-mcp-conformance`, an opt-in tagged ExUnit wrapper, and
  `docs/mcp-client-conformance.md`. The matrix names all harness scenarios selected for
  `2025-11-25`: OAuth and elicitation are out of this milestone's scope, while `sse-retry`
  remains pending and is not represented as a pass.
- The initial manual red harness run saved diagnostic results under `/tmp`; no generated
  result directory or dependency install is committed.

## Sources

- [ExMCP 1.3.0 package](https://hex.pm/packages/ex_mcp/1.3.0)
- [ExMCP client API](https://ex-mcp.hexdocs.pm/ExMCP.Client.html)
- [MCP 2025-11-25 Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [Official conformance SDK guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md)
