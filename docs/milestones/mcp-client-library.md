# Anubis MCP integration and conformance

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: None beyond the existing umbrella and project hygiene. No room, database, telephony or model provider is required. Its placement before remote tool integration is owned by the index.
Sources: [Anubis documentation](https://anubis-mcp.hexdocs.pm/readme.html); [Anubis package](https://hex.pm/packages/anubis_mcp); [approved remote profile](../../labnotes/20260905-0405-call-definition-design.md#initial-remote-protocol-and-input-validation--approved-r22r23); [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle); [Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports); [official client conformance framework](https://github.com/modelcontextprotocol/conformance); [harness integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md); [Everything reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/everything).

## Runnable outcome

A standalone command uses Anubis through Vxpipe's thin internal integration layer to discover and call a remote test tool, then runs applicable official client-conformance scenarios. This verifies the configured dependency boundary without starting a voice room or requiring an LLM or database.

## Specification

- Select `anubis_mcp` as the MCP client dependency. `vxpipe_mcp` is a thin internal Mix integration library/umbrella child around it, not a new MCP client codebase. Anubis owns JSON-RPC, HTTP/SSE parsing, negotiation, protocol requests and transport lifecycle. The wrapper owns configured supervision, Vxpipe-facing results and enforcement of project-owned boundary policies; it has no call-engine, Calls, persistence or gateway dependency.
- Target MCP `2025-11-25` Streamable HTTP with JSON and SSE responses, replacing the earlier `2026-07-28` target. Anubis 2.0.0 is the inspected published release; pin the compatible dependency at implementation and record its exact version/lockfile. Use `initialize`/`notifications/initialized`, the negotiated `MCP-Protocol-Version` header and any server-issued session ID through Anubis, not stateless per-request negotiation. Reject revisions outside Vxpipe's tested profile even if the SDK supports others.
- Do not implement missing protocol pieces ourselves or silently fork/fallback to a second client. If the selected release cannot meet an acceptance gate, report the specific upstream/configuration gap for resolution instead of weakening the contract or claiming interoperability.
- Accept explicit resolved endpoint, private credentials, outbound-network policy, deadlines and limits. The Vxpipe integration layer owns tenant/app selection, credential resolution, enabled-tool grants, call/agent lifetimes, catalog scope and history. The library cannot consult tenant records or infer permissions from server descriptions.
- Preserve the existing verified-HTTPS/address-at-connect/no-redirect credential safeguards at the actual HTTP boundary. Apply decoded/decompressed byte limits during receipt; bound malformed framing/correlation behavior and preserve definite non-submission versus unknown submitted outcomes. No automatic tools/call retry or server-requested continuation.
- Consume Anubis discovery/results and validate outgoing arguments against the supplied pinned schema with a proper JSON Schema validator before invocation. Verify SDK coverage before relying on it; a schema builder is not proof of runtime argument validation. Do not duplicate protocol parsing or fetch external schema references automatically.
- Bound a whole paginated discovery operation by deadline and aggregate page/byte budgets,
  not only each response. Repeated cursors or exhausted budgets fail discovery explicitly;
  never publish a partial catalog as complete or expose unresolved selected bindings.
- Keep negotiated/session state scoped to the resolved integration and credential generation. Establish readiness before discovery/invocation. SDK reconnection or SSE stream resumption must not resubmit an uncertain `tools/call`; session expiry, timeout and disconnect retain honest unknown outcomes where submission occurred. Unsupported sampling/elicitation/tasks capabilities stay unadvertised despite SDK availability.
- Preserve the same invocation's absolute deadline and cumulative decoded/decompressed
  byte budget across SSE GET resumption, progress notifications and SDK reconnection.
  Neither a new HTTP response nor a progress event resets these project-owned bounds.
- Treat the pinned official specification/schema as normative. The official conformance framework's client mode supplies scenario servers; add a small executable client driver for its documented interface, not a second MCP implementation just for passing tests. Pin the framework revision/package, protocol version, chosen scenarios and any reference server version in the implementation evidence.
- The Everything server is an additional client-builder reference, not proof of every protocol requirement. Confirm the pinned server supports the intended revision and remote transport; otherwise use a matching official scenario server or document the gap, never downgrade the declared supported profile silently.
- Upstream harness loopback HTTP belongs only to an explicit isolated test runner/transport configuration. It must not become a tenant-selectable insecure mode, a production default, or a way to bypass HTTPS/private-network policy.
- Record pass/fail/not-applicable per supported requirement. Unsupported optional OAuth/interaction scenarios do not expand product scope; failures in claimed support remain failures. Conformance results are interoperability evidence, not certification or replacement for project-owned security/timeout/limit tests.
- Anubis's LGPL-3.0 packaging obligations remain a release-verification concern, not a commercial-use prohibition. Record the pinned dependency's notices, corresponding-source and replacement/relinking arrangements for the distributed image; do not treat SDK adoption as completed license compliance.

## Implementation checklist

- [ ] Verify/pin the Anubis release against the selected profile and project-owned security, size-limit, timeout and no-resubmission requirements; report unmet gates without a custom-client fallback.
- [ ] Red-test the smallest Vxpipe adapter contract, then add Anubis to the owning internal library with its lockfile; do not duplicate dependency-owned unit tests.
- [ ] Wire configured Anubis supervision/readiness, discovery and validated tool calls, including bounded failures and cleanup.
- [ ] Add the official client-conformance driver, pinned harness/reference inputs and a documented supported-requirement matrix.
- [ ] Add an opt-in tagged integration lane; keep deterministic contract/security tests in the library's own test suite.
- [ ] Document the internal public API for the later room integration without exporting room/tenant/DB abstractions.

## Acceptance and failure checks

- [ ] Standalone client discovers and calls a reference tool with neither database nor call engine running.
- [ ] Applicable pinned official client scenarios pass; omitted/unsupported scenarios and upstream harness defects are explicit, not blanket success.
- [ ] Negotiated-version mismatch, malformed/error responses, wrong correlation IDs and unsupported interactions fail safely through the configured client without speculative resubmission.
- [ ] Argument schema failure occurs before network submission; external schema refs do not trigger hidden fetches.
- [ ] Repeated cursors, endless pages and aggregate discovery limits stop without an
  unbounded loop or a falsely complete catalog; subsequent calls cannot use partial bindings.
- [ ] Oversized compressed/chunked/SSE responses stop incrementally at the configured limit; timeout/disconnect retains honest unknown outcomes where submission occurred.
- [ ] Credentials are absent from diagnostics/status; redirects, changed DNS/private addresses and credential forwarding obey production policy.
- [ ] Test-only loopback harness settings cannot be selected through ordinary production integration configuration.
- [ ] Client cleanup is bounded, separate invocations remain isolated, and dependency checks show no room/Repo/Gateway ownership in the library.
- [ ] Initialization completes before discovery both with and without a server-issued session ID; session IDs/credentials do not cross integration boundaries. Session expiry and SDK reconnect paths never repeat an uncertain tool invocation.
- [ ] Break/resume a response stream: the original deadline and cumulative byte budget
  still apply, including across progress events and repeated reconnects.

## Manual verification

1. Run the documented Anubis-backed command against a pinned `2025-11-25` remote-transport server through the explicit test harness.
2. Discover tools and invoke a synthetic echo/structured-result operation; inspect safe protocol results.
3. Run the official framework in client-testing mode for the supported profile and save its scenario matrix and versions.
4. Run malformed, slow, oversized and unsafe-endpoint cases. Confirm actual enforcement and no extra request on uncertain failure.
5. Run the production transport configuration separately with verified HTTPS; test-mode success is not production-network proof.

## Scope boundaries

No custom MCP protocol/client implementation, public MCP server feature, stdio runtime integration, full multi-version promise, OAuth onboarding, generic resources/prompts application UI, server-requested sampling/elicitation, auto-fetching documents or remote task/cancellation framework. Room authorization, tool conversation and archival integration follow in the remote-MCP milestone.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08. Added whole-discovery
page/byte/deadline bounds and repeated-cursor/endless-pagination/incomplete-catalog checks.
That review covered the earlier SDK-unspecified boundary. The subsequent user-approved
Anubis selection and `2025-11-25` profile passed milestone_review_a's focused follow-up
review, including deadline/byte budgets across resumed streams and initialization with
and without session IDs. The filename, index position and standalone outcome are retained.
This is specification evidence only; implementation and runtime verification remain unchecked.
