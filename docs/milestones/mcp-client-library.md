# Jido MCP integration and conformance

Status: not implemented. Specification review: approved, including the Jido MCP
follow-up (2026-09-08). Implementation blocker: the reviewed public dynamic-tool sync
requires trusted atom endpoint IDs and creates runtime Action modules from discovered
tool definitions; that cannot safely represent tenant-configured catalogs yet.
Prerequisites: [Definition-driven call](definition-driven-call.md), including its
Jido AI/Jido Action runtime boundary. No room, database, telephony or live model provider
is required for this standalone checkpoint.
Sources: [Jido MCP package](https://hex.pm/packages/jido_mcp); [Jido MCP integration](https://hexdocs.pm/jido_mcp/readme.html); [Jido evaluation](../../labnotes/20260908-1344-jido-ai-evaluation.md); [approved remote profile](../../labnotes/20260905-0405-call-definition-design.md#initial-remote-protocol-and-input-validation--approved-r22r23); [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle); [Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports); [official client conformance framework](https://github.com/modelcontextprotocol/conformance); [harness integration guide](https://github.com/modelcontextprotocol/conformance/blob/main/SDK_INTEGRATION.md); [Everything reference server](https://github.com/modelcontextprotocol/servers/tree/main/src/everything).

## Runnable outcome

A standalone command uses Jido MCP through Vxpipe's thin internal integration layer to
discover and call a remote test tool, exposes that tool to a deterministic Jido AI run, and
runs applicable official client-conformance scenarios. This verifies the configured
dependency boundary without starting a voice room, database, or live model provider.

## Specification

- Select `jido_mcp` as Vxpipe's direct MCP integration dependency. `vxpipe_mcp` is a thin
  internal Mix library/umbrella child around Jido MCP, not a new MCP client codebase. Jido
  MCP owns protocol requests, negotiation, wire parsing, client pooling and transport
  lifecycle through its public API. Its choice of transitive protocol/transport library is
  an internal Jido detail and may change without changing Vxpipe architecture.
- Use Jido MCP's public discovery/invocation API and its supported Jido Action/Jido AI tool
  integration with the per-activation Jido AgentServer. Do not call or configure a
  transitive MCP client library directly from Vxpipe, depend on private Jido modules, or
  maintain a second client path.
- Target MCP `2025-11-25` Streamable HTTP with JSON and SSE responses, replacing the earlier
  `2026-07-28` target. Pin a compatible Jido MCP release at implementation and record its
  exact version/lockfile. Exercise `initialize`/`notifications/initialized`, the negotiated
  `MCP-Protocol-Version` header and any server-issued session ID through Jido MCP. Reject
  revisions outside Vxpipe's tested profile even if Jido MCP supports others.
- If the selected Jido MCP release cannot meet a required acceptance gate, report the
  concrete compatibility gap and resolve it at the Jido MCP boundary. Do not silently add a
  direct transitive-client dependency, custom parser, second protocol path, or weaker
  product contract.
- Accept explicit resolved endpoint, private credentials, outbound-network policy, deadlines
  and limits. The Vxpipe integration owner retains application/tenant selection, credential
  resolution, enabled-tool grants, call/agent lifetimes, catalog scope and history. The
  library cannot consult tenant records or infer permissions from server descriptions.
- Keep endpoint/tool identifiers bounded and safe for externally configured tenant data.
  Jido MCP integration must not create atoms or Action modules from an unbounded sequence of
  tenant endpoint IDs, local aliases, remote tool names, descriptions, or schema revisions.
  The currently reviewed public sync path requires a trusted atom endpoint ID and generates
  proxy modules whose names vary with discovered tool definitions. Purging module code does
  not garbage-collect its atom. Therefore resolve this through a supported public Jido
  MCP/Jido AI data-backed or otherwise lifetime-bounded tool surface before implementation;
  do not call its private proxy generator.
- Do not substitute the generic `Jido.MCP.Actions.CallTool` as the model-visible product
  contract. Its model-supplied endpoint/tool selector and generic arguments map do not
  preserve the call plan's local aliases and pinned per-tool input schemas. A future public
  Jido integration must expose each authorized local binding with its exact schema while
  keeping endpoint selection private.
- Enforce verified HTTPS, address-at-connect/rebinding checks and no redirect credential
  forwarding at the effective outbound boundary. Apply decoded/decompressed byte limits
  during receipt; preserve definite non-submission versus unknown submitted outcomes. Jido
  Action and ReAct automatic tool retries remain configured off for side-effecting calls.
- Discover remote schemas through Jido MCP and validate actual outgoing arguments against
  the pinned `inputSchema` with a proper JSON Schema 2020-12 validator before invocation.
  Verify the effective Jido path rather than assuming tool-schema conversion proves runtime
  validation. Do not fetch external schema references automatically.
- Bound a whole paginated discovery operation by deadline and aggregate page/byte budgets,
  not only each response. Repeated cursors or exhausted budgets fail discovery explicitly;
  never publish a partial catalog as complete or expose unresolved selected bindings.
- Scope pooled/session state to the resolved integration and credential generation.
  Establish readiness before discovery/invocation. Reconnection or stream resumption must
  not resubmit an uncertain `tools/call`; the same invocation retains one absolute deadline
  and cumulative decoded/decompressed byte budget across responses and progress events.
- Treat the pinned official specification/schema as normative. The conformance framework's
  client mode supplies scenario servers; build only the documented Jido MCP driver needed to
  run those scenarios. Pin framework/protocol/reference versions and record each applicable
  pass, failure and unsupported/skipped case rather than claiming blanket certification.
- The Everything server is an additional interoperability fixture, not proof of every
  protocol requirement. Confirm that the pinned server supports the intended revision and
  remote transport. Loopback HTTP is allowed only inside the isolated test runner and never
  through normal application/tenant configuration.

## Implementation checklist

- [ ] Verify and pin a Jido MCP release against the selected profile and project-owned
  security, identity, size-limit, timeout and no-resubmission requirements.
- [ ] Resolve the dynamic tenant-tool blocker through a public Jido API that preserves local
  binding names and pinned schemas without externally driven atom/module growth; record the
  exact supported mechanism before adding the dependency.
- [ ] Red-test the smallest `vxpipe_mcp` contract, then add Jido MCP to the owning internal
  library with its lockfile; do not depend directly on Jido MCP's transitive client runtime.
- [ ] Wire configured Jido MCP supervision/readiness, discovery and validated invocation,
  including bounded failure and cleanup behavior.
- [ ] Expose a discovered test tool through the established Jido Action/AI boundary without
  leaking tenant credentials or creating unbounded atoms/modules.
- [ ] Add the official client-conformance driver, pinned harness/reference inputs and a
  documented supported-requirement matrix.
- [ ] Add an opt-in tagged integration lane; keep deterministic contract/security tests in
  the library's own test suite.
- [ ] Document the internal public API for later room integration without exporting
  room/tenant/database abstractions.

## Acceptance and failure checks

- [ ] A standalone Jido MCP client discovers/calls a reference tool and a scripted Jido AI
  run invokes its exposed action with neither database nor call engine running.
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

1. Run the documented Jido MCP command against a pinned `2025-11-25` remote-transport
   server through the explicit test harness.
2. Discover tools, invoke a synthetic structured-result operation, and expose the same tool
   to a deterministic Jido AI run; inspect normalized safe results.
3. Run the official framework in client-testing mode and save its scenario matrix and
   versions.
4. Run malformed, slow, oversized, unsafe-endpoint and repeated-catalog cases. Confirm the
   effective public Jido MCP path enforces policy and emits no extra uncertain request.
5. Run production transport configuration separately with verified HTTPS; test-mode success
   is not production-network proof.

## Scope boundaries

No direct dependency on Jido MCP's transitive client runtime, custom MCP protocol/client
implementation, public MCP server feature, local/stdio product integration, full
multi-version promise, OAuth onboarding, generic resources/prompts UI, server-requested
sampling/elicitation, auto-fetching documents, or remote cancellation framework. Room
authorization, background conversation and archival integration follow in the remote-MCP
milestone. A generic model-visible endpoint/tool dispatcher or use of Jido MCP private proxy
modules is not an acceptable workaround for the compatibility blocker.

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
The corrected specification is approved with that explicit implementation blocker. The
filename, index position and standalone outcome are retained. This is specification evidence only;
implementation and runtime verification remain unchecked.
