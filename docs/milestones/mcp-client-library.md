# Internal MCP client and conformance

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: None beyond the existing umbrella and project hygiene. No room, database, telephony or model provider is required. Its placement before remote tool integration is owned by the index.
Sources: [Approved remote profile](../../labnotes/20260905-0405-call-definition-design.md#initial-remote-protocol-and-input-validation--approved-r22r23); [official specification](https://modelcontextprotocol.io/specification/2026-07-28); [official client conformance framework](https://github.com/modelcontextprotocol/conformance); [harness integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md); [Everything reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/everything).

## Runnable outcome

A standalone client command uses the internal MCP library to discover and call a remote test tool, then runs the applicable official client-conformance scenarios. This proves the protocol boundary without starting a voice room or requiring an LLM or database.

## Specification

- Isolate protocol support in `vxpipe_mcp`, a separate internal Mix library/umbrella child. Own JSON-RPC encoding/decoding, revision-specific metadata and transport lifecycle, discovery/tool requests, response/error normalization and bounded network I/O. Do not depend on the call engine, Calls, persistence or gateway; declare actual dependency direction in Mix.
- Prefer a compatible maintained SDK behind this boundary. First demonstrate the approved `2026-07-28` Streamable HTTP JSON/request-scoped SSE profile; implement only needed unsupported pieces if no suitable dependency covers it. Separate ownership is not a request to implement every MCP feature or publish a new SDK.
- Accept explicit resolved endpoint, private credentials, outbound-network policy, deadlines and limits. The Vxpipe integration layer owns tenant/app selection, credential resolution, enabled-tool grants, call/agent lifetimes, catalog scope and history. The library cannot consult tenant records or infer permissions from server descriptions.
- Preserve the existing verified-HTTPS/address-at-connect/no-redirect credential safeguards at the actual HTTP boundary. Apply decoded/decompressed byte limits during receipt; bound malformed framing/correlation behavior and preserve definite non-submission versus unknown submitted outcomes. No automatic tools/call retry or server-requested continuation.
- Expose discovered schemas and use a proper validator for outgoing arguments; document which protocol/wire checks and tool-input checks the library owns so the engine does not implement a second protocol parser. Supplied pinned schemas remain authoritative for an invocation; no automatic external schema-reference fetching.
- Bound a whole paginated discovery operation by deadline and aggregate page/byte budgets,
  not only each response. Repeated cursors or exhausted budgets fail discovery explicitly;
  never publish a partial catalog as complete or expose unresolved selected bindings.
- Treat the pinned official specification/schema as normative. The official conformance framework's client mode supplies scenario servers; add a small executable client driver for its documented interface, not a second MCP implementation just for passing tests. Pin the framework revision/package, protocol version, chosen scenarios and any reference server version in the implementation evidence.
- The Everything server is an additional client-builder reference, not proof of every protocol requirement. Confirm the pinned server supports the intended revision and remote transport; otherwise use a matching official scenario server or document the gap, never downgrade the declared supported profile silently.
- Upstream harness loopback HTTP belongs only to an explicit isolated test runner/transport configuration. It must not become a tenant-selectable insecure mode, a production default, or a way to bypass HTTPS/private-network policy.
- Record pass/fail/not-applicable per supported requirement. Unsupported optional OAuth/interaction scenarios do not expand product scope; failures in claimed support remain failures. Conformance results are interoperability evidence, not certification or replacement for project-owned security/timeout/limit tests.

## Implementation checklist

- [ ] Assess current SDK support against the pinned remote profile and record reuse versus missing-implementation decisions.
- [ ] Red-test the smallest protocol/client boundary, then create the internal library with only directly owned dependencies.
- [ ] Implement discovery and validated tool calls over the supported remote JSON/SSE profile, including bounded failures and cleanup.
- [ ] Add the official client-conformance driver, pinned harness/reference inputs and a documented supported-requirement matrix.
- [ ] Add an opt-in tagged integration lane; keep deterministic contract/security tests in the library's own test suite.
- [ ] Document the internal public API for the later room integration without exporting room/tenant/DB abstractions.

## Acceptance and failure checks

- [ ] Standalone client discovers and calls a reference tool with neither database nor call engine running.
- [ ] Applicable pinned official client scenarios pass; omitted/unsupported scenarios and upstream harness defects are explicit, not blanket success.
- [ ] Revision/metadata mismatch, malformed/error responses, wrong correlation IDs and unsupported interactions fail safely without speculative resubmission.
- [ ] Argument schema failure occurs before network submission; external schema refs do not trigger hidden fetches.
- [ ] Repeated cursors, endless pages and aggregate discovery limits stop without an
  unbounded loop or a falsely complete catalog; subsequent calls cannot use partial bindings.
- [ ] Oversized compressed/chunked/SSE responses stop incrementally at the configured limit; timeout/disconnect retains honest unknown outcomes where submission occurred.
- [ ] Credentials are absent from diagnostics/status; redirects, changed DNS/private addresses and credential forwarding obey production policy.
- [ ] Test-only loopback harness settings cannot be selected through ordinary production integration configuration.
- [ ] Client cleanup is bounded, separate invocations remain isolated, and dependency checks show no room/Repo/Gateway ownership in the library.

## Manual verification

1. Run the documented client against a pinned local/reference remote-transport server through the explicit test harness.
2. Discover tools and invoke a synthetic echo/structured-result operation; inspect safe protocol results.
3. Run the official framework in client-testing mode for the supported profile and save its scenario matrix and versions.
4. Run malformed, slow, oversized and unsafe-endpoint cases. Confirm actual enforcement and no extra request on uncertain failure.
5. Run the production transport configuration separately with verified HTTPS; test-mode success is not production-network proof.

## Scope boundaries

No public MCP server feature, stdio runtime integration, full multi-version SDK promise, OAuth onboarding, generic resources/prompts application UI, server-requested sampling/elicitation, auto-fetching documents or remote task/cancellation framework. Room authorization, tool conversation and archival integration follow in the remote-MCP milestone.

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
Focused re-review approved the library and downstream integration boundary; the standalone
client outcome, official conformance/reference approach and index order are appropriate.
This is specification evidence only; implementation and runtime verification remain unchecked.
