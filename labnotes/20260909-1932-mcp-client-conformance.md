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

## Sources

- [ExMCP 1.3.0 package](https://hex.pm/packages/ex_mcp/1.3.0)
- [ExMCP client API](https://ex-mcp.hexdocs.pm/ExMCP.Client.html)
- [MCP 2025-11-25 Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [Official conformance SDK guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md)
