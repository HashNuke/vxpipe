# MCP client integration and conformance

Status: in progress. The exact dependency/profile, bounded all-or-nothing discovery,
pre-submission validated invocation, scoped supervised connection contracts, two unmodified
official scenarios, corrected recovery fixture, and Everything-server interoperability are
implemented. Credentialed production and remaining failure/security gates remain unproven;
the separate Jido runtime-tool interface blocker belongs to the live-MCP milestone, not this
library.
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
- [x] Red-test the smallest `vxpipe_mcp` contract, then add ExMCP to the owning internal
  library with its lockfile; keep Jido/domain dependencies out of this child.
- [x] Wire configured ExMCP supervision/readiness, discovery and validated invocation,
  including bounded failure and cleanup behavior.
- [x] Return a discovered test tool as schema/name data without credential leakage or
  externally driven atom/module creation; leave Jido exposure to the live-MCP milestone.
- [x] Add the official client-conformance driver, pinned harness/reference inputs and a
  documented supported-requirement matrix.
- [x] Add an opt-in tagged integration lane; keep deterministic contract/security tests in
  the library's own test suite.
- [x] Document the internal public API for later room integration without exporting
  room/tenant/database abstractions.

## Acceptance and failure checks

- [x] A standalone ExMCP-backed wrapper discovers/calls a reference tool with neither
  Jido nor database/call engine running; decoded names/schemas remain data.
- [x] Applicable pinned official client scenarios pass; omitted/unsupported scenarios and
  upstream harness defects are explicit, not blanket success.
- [x] Negotiated-version mismatch, malformed/error responses, wrong correlation IDs and
  unsupported interactions fail safely without speculative resubmission.
- [x] Argument schema failure occurs before network submission; external schema refs do not
  trigger hidden fetches.
- [x] Repeated cursors, endless pages and aggregate discovery limits stop without an
  unbounded loop or falsely complete catalog; partial bindings cannot be invoked.
- [x] Oversized compressed/chunked/SSE responses stop incrementally at the configured limit;
  timeout/disconnect retains an honest unknown outcome after submission.
- [ ] Credentials are absent from diagnostics/status; redirects, changed DNS/private
  addresses and credential forwarding obey production policy.
- [x] Test-only loopback settings cannot be selected through production integration config.
- [x] Repeatedly register and retire bounded test catalogs; externally supplied identifiers
  do not cause atom/module growth proportional to tenant/catalog churn or cross-tenant tool
  resolution. Measure BEAM atom/module counts across many unique endpoint, tool and schema
  revisions rather than checking only live proxy cleanup.
- [x] Initialization completes before discovery with and without a server-issued session ID;
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

Implementation evidence:

- The `vxpipe_mcp` child pins ExMCP 1.3.0 and owns no Jido/domain dependency. Its fixed
  production client profile accepts verified HTTPS only and selects MCP `2025-11-25`.
- `Vxpipe.MCP.Discovery` obtains every page through the narrow protocol boundary under one
  absolute deadline and aggregate decoded-JSON budget. It rejects repeated cursors and
  returns no partial catalog. `Vxpipe.MCP.Catalog` preserves complete string-keyed remote
  definitions while rejecting malformed or duplicate tool identities.
- Deterministic discovery checks cover repeated and endlessly changing cursors, cumulative
  decoded size across pages, malformed page shapes, duplicate identities, and the page cap.
  Dependency failures become the credential-free `:discovery_failed` category rather than
  exposing raw diagnostics.
- A synchronous churn test creates 250 unique endpoint hosts, integration IDs, credential
  generations, tool names, and schema revisions, opening and retiring each supervised
  connection. BEAM atom and loaded-module growth remain below a fixed five-item ceiling
  rather than scaling with the supplied identities. Same-named tools in two catalogs also
  resolve only from the catalog value explicitly supplied by the caller; there is no global
  remote-name registry in this library.
- Effective loopback wire tests cover server JSON-RPC failures, method-not-found responses,
  malformed JSON, and wrong correlation IDs through the supervised ExMCP client. Remote and
  unsupported errors become `:remote_error`; malformed and mismatched responses preserve the
  honest `:outcome_unknown` state. Every case emits exactly one `tools/call`.
- Effective 1 KiB response-limit tests reject content encoding entirely and observe
  `:response_too_large` for oversized chunked JSON and POST SSE bodies. A delayed response
  beyond a 100 ms deadline and a server-side disconnect both return `:outcome_unknown`.
  All five post-submission failures emit one tool call and no retry. Cumulative accounting
  across resumed streams remains a separate unchecked gate.
- `Vxpipe.MCP.Invocation` selects only from that complete catalog and delegates schema work
  to `Vxpipe.MCP.ArgumentValidator`. Default/explicit JSON Schema 2020-12 and canonical
  explicit Draft 7 arguments are checked without casts or remote resolvers before submission;
  unknown tools, invalid arguments, unsupported schemas, and oversized decoded results
  return bounded categorical errors. The ExMCP-only
  adapter uses the single-request `tools/call` path with generic and ambiguous stream replay
  disabled.
- `Vxpipe.MCP.Connections` scopes a supervised client subtree to a bounded resolved
  integration identity plus credential generation. It reuses only that exact generation,
  returns a credential-free opaque handle after exact-version readiness, and retires the
  owning subtree through its `DynamicSupervisor`; connection registry, runtime adapter,
  identity, handle, and subtree supervision remain separate modules.
- Production client construction is HTTPS-only and supplies explicit bounded request,
  response, stream-buffer, DNS, connect, and request settings to ExMCP. A separate
  loopback-only builder exists for isolated fixtures; adding `test_mode` to ordinary
  production configuration cannot select plaintext transport.
- `mix vxpipe.mcp.conformance_client` starts only `:vxpipe_mcp` and dispatches the two
  unmodified official scenarios plus the corrected recovery action. The pinned opt-in
  runner and tagged integration lane reproduce MCP `2025-11-25` initialization and one
  discovered/validated `tools/call`; the full scenario matrix and internal API are recorded in
  [MCP client conformance profile](../mcp-client-conformance.md).
- The focused behavior test was observed red before implementation and is green with the
  default child suite (25 tests, 0 failures, three integration tests excluded). The opt-in
  lane passes all three wrapper tests: the two unmodified harness scenarios each score 1/1,
  the corrected recovery fixture scores 3/3, and the Everything probe returns its expected
  tool and result. This is partial conformance evidence, not a blanket claim.
- The unmodified official `sse-retry` scenario is explicitly rejected because its
  `2025-11-25`-tagged server negotiates `2025-03-26`. A reproducible one-line
  exact-version correction against the verified tag commit passes 3/3, including the
  500 ms retry interval, `Last-Event-ID`, original-result delivery, and only one observed
  `tools/call`. This is corrected-fixture evidence, not an official-pass claim.
- The additional Everything fixture is pinned to tag `2026.8.31` / commit `a40bc270`, whose
  lockfile selects MCP SDK `1.30.0`. Its Streamable HTTP server negotiates `2025-11-25`,
  issues a session ID, publishes an explicit Draft 7 `echo` schema, and returns the expected
  result through the standalone Vxpipe probe. The earlier date-matched server package was
  rejected because its locked SDK supports only revisions through `2025-06-18`.

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
