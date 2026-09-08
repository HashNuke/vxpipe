# MCP client integration and conformance

Status: not implemented. Specification updated after the 2026-09-08 released-package
investigation. ExMCP compatibility/conformance gates remain unproven; the separate Jido
runtime-tool interface blocker belongs to the live-MCP milestone, not this library.
Prerequisites: none beyond the existing umbrella. No Jido runtime, room, database,
telephony or model provider is required for this standalone checkpoint.
Sources: [ExMCP package](https://hex.pm/packages/ex_mcp); [ExMCP client](https://hexdocs.pm/ex_mcp/ExMCP.Client.html); [loop/tool-binding decision](../jido-tool-execution.md); [approved remote profile](../../labnotes/20260905-0405-call-definition-design.md#initial-remote-protocol-and-input-validation--approved-r22r23); [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle); [Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports); [official client conformance framework](https://github.com/modelcontextprotocol/conformance); [harness integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md); [Everything reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/everything).

## Runnable outcome

A standalone command uses ExMCP through Vxpipe's thin internal integration layer to
discover and call a remote test tool and runs applicable official client-conformance
scenarios. This verifies the protocol/policy boundary without starting Jido, a voice
room, database or model provider. Model exposure is verified in the live-MCP slice.

## Specification

- Select `ex_mcp` directly in `vxpipe_mcp`, a thin internal Mix library/umbrella child,
  not a new MCP client codebase. ExMCP owns protocol requests, negotiation, wire parsing
  and transport lifecycle through its public client API. The wrapper owns configured
  supervision, scoped client reuse and Vxpipe policy/result mapping.
- Use public `ExMCP.Client` discovery/invocation APIs. This library depends on neither
  Jido AI/Action nor `jido_mcp`/Jido Connect. The engine-side bridge integrates model
  tools later. Do not use private dependency modules or maintain a second client path.
- Target MCP `2025-11-25` Streamable HTTP with JSON and SSE responses, replacing the earlier
  `2026-07-28` target. Evaluate ExMCP 1.3.0, pin a compatible release and record its
  exact version/lockfile. Exercise `initialize`/`notifications/initialized`, the negotiated
  `MCP-Protocol-Version` header and any server-issued session ID through ExMCP. Configure
  the explicit legacy-only `2025-11-25` profile and reject other negotiated revisions.
  Broader dependency support is not broader Vxpipe support.
- If ExMCP cannot meet a required acceptance gate, report the concrete compatibility gap
  and resolve it at its public boundary. Do not silently add a custom parser, second
  protocol path or weaker product contract.
- Accept explicit resolved endpoint, private credentials, outbound-network policy, deadlines
  and limits. The Vxpipe integration owner retains application/tenant selection, credential
  resolution, enabled-tool grants, call/agent lifetimes, catalog scope and history. The
  library cannot consult tenant records or infer permissions from server descriptions.
- Keep endpoint/tool identifiers and schemas as bounded data. Do not create atoms or
  Action modules from tenant IDs, local aliases, remote names, descriptions or schema
  revisions. Return discovered schemas intact to the integration owner; this library
  neither generates Jido Actions nor publishes a model-visible endpoint/tool dispatcher.
- Enforce verified HTTPS, address-at-connect/rebinding checks and no redirect credential
  forwarding at the effective outbound boundary. Apply decoded/decompressed byte limits
  during receipt; preserve definite non-submission versus unknown submitted outcomes.
  Disable automatic invocation retries and verify stream recovery independently of the
  generic retry policy; dependency defaults are not proof of no resubmission.
- Discover remote schemas through ExMCP and validate actual outgoing arguments against
  the pinned `inputSchema` with a proper JSON Schema 2020-12 validator before invocation.
  Verify the effective client path rather than assuming a bundled validator or model-schema
  conversion proves 2020-12 runtime validation. Do not fetch external schema references automatically.
- Bound a whole paginated discovery operation by deadline and aggregate page/byte budgets,
  not only each response. Repeated cursors or exhausted budgets fail discovery explicitly;
  never publish a partial catalog as complete or expose unresolved selected bindings.
- Scope pooled/session state to the resolved integration and credential generation.
  Establish readiness before discovery/invocation. Reconnection or stream resumption must
  not resubmit an uncertain `tools/call`; the same invocation retains one absolute deadline
  and cumulative decoded/decompressed byte budget across responses and progress events.
- Treat the pinned official specification/schema as normative. The conformance framework's
  client mode supplies scenario servers; build only the documented ExMCP wrapper driver needed to
  run those scenarios. Pin framework/protocol/reference versions and record each applicable
  pass, failure and unsupported/skipped case rather than claiming blanket certification.
- The Everything server is an additional interoperability fixture, not proof of every
  protocol requirement. Confirm that the pinned server supports the intended revision and
  remote transport. Loopback HTTP is allowed only inside the isolated test runner and never
  through normal application/tenant configuration.

## Implementation checklist

- [ ] Verify and pin an ExMCP release against the selected profile and project-owned
  security, identity, size-limit, timeout and no-resubmission requirements.
- [ ] Red-test the smallest `vxpipe_mcp` contract, then add ExMCP to the owning internal
  library with its lockfile; keep Jido/domain dependencies out of this child.
- [ ] Wire configured ExMCP supervision/readiness, discovery and validated invocation,
  including bounded failure and cleanup behavior.
- [ ] Return a discovered test tool as schema/name data without credential leakage or
  externally driven atom/module creation; leave Jido exposure to the live-MCP milestone.
- [ ] Add the official client-conformance driver, pinned harness/reference inputs and a
  documented supported-requirement matrix.
- [ ] Add an opt-in tagged integration lane; keep deterministic contract/security tests in
  the library's own test suite.
- [ ] Document the internal public API for later room integration without exporting
  room/tenant/database abstractions.

## Acceptance and failure checks

- [ ] A standalone ExMCP-backed wrapper discovers/calls a reference tool with neither
  Jido nor database/call engine running; decoded names/schemas remain data.
- [ ] Applicable pinned official client scenarios pass; omitted/unsupported scenarios and
  upstream harness defects are explicit, not blanket success.
- [ ] Negotiated-version mismatch, malformed/error responses, wrong correlation IDs and
  unsupported interactions fail safely without speculative resubmission.
- [ ] Argument schema failure occurs before network submission; external schema refs do not
  trigger hidden fetches.
- [ ] Repeated cursors, endless pages and aggregate discovery limits stop without an
  unbounded loop or falsely complete catalog; partial bindings cannot be invoked.
- [ ] Oversized compressed/chunked/SSE responses stop incrementally at the configured limit;
  timeout/disconnect retains an honest unknown outcome after submission.
- [ ] Credentials are absent from diagnostics/status; redirects, changed DNS/private
  addresses and credential forwarding obey production policy.
- [ ] Test-only loopback settings cannot be selected through production integration config.
- [ ] Repeatedly register and retire bounded test catalogs; externally supplied identifiers
  do not cause atom/module growth proportional to tenant/catalog churn or cross-tenant tool
  resolution. Measure BEAM atom/module counts across many unique endpoint, tool and schema
  revisions rather than checking only live proxy cleanup.
- [ ] Initialization completes before discovery with and without a server-issued session ID;
  sessions/credentials do not cross integration generations and reconnect never repeats an
  uncertain invocation.
- [ ] Break/resume a response stream: the original deadline and cumulative byte budget still
  apply across responses, progress events and reconnects.

## Manual verification

1. Run the documented ExMCP wrapper command against a pinned `2025-11-25` remote-transport
   server through the explicit test harness.
2. Discover tools and invoke a synthetic structured-result operation; inspect normalized
   safe results and preserved catalog/schema data without a model runtime.
3. Run the official framework in client-testing mode and save its scenario matrix and
   versions.
4. Run malformed, slow, oversized, unsafe-endpoint and repeated-catalog cases. Confirm the
   effective public ExMCP path enforces policy and emits no extra uncertain request.
5. Run production transport configuration separately with verified HTTPS; test-mode success
   is not production-network proof.

## Scope boundaries

No Jido model-tool registration, custom MCP protocol/client implementation, public MCP
server feature, local/stdio product integration, full
multi-version promise, OAuth onboarding, generic resources/prompts UI, server-requested
sampling/elicitation, auto-fetching documents, or remote cancellation framework. Room
authorization, background conversation and archival integration follow in the remote-MCP
milestone. Passing this checkpoint does not resolve Jido AI's runtime-tool interface gap.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

The earlier client-library and `2025-11-25` behavior contracts were independently reviewed
by milestone_review_a on 2026-09-08, including discovery bounds, resumed-stream budgets and
optional-session initialization. The 2026-09-08 Jido follow-up inspected the current public
discovery, invocation, Agent sync, proxy-generation and cleanup paths. It approved the
AgentServer integration boundary but found externally driven atom/module growth in the
dynamic proxy path and rejected the generic call action as a schema/authority workaround.
The subsequent released-package investigation selected direct ExMCP and moved Jido tool
exposure out of this protocol-only checkpoint into the live-MCP milestone. Existing
protocol/security acceptance gates remain; see [the decision](../jido-tool-execution.md).
The filename and index position are retained. This is specification evidence only;
implementation and runtime verification remain unchecked.
