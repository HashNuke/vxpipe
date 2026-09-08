# Remote MCP tools in a live call

Status: not implemented. Specification review: approved baseline (2026-09-08);
Jido MCP follow-up review pending.
Prerequisites: [Asynchronous history](asynchronous-call-history.md), including its background-tool and tenant admission prerequisites; [Jido MCP integration and conformance](mcp-client-library.md).
Sources: [Configured integrations](../../labnotes/20260905-0405-call-definition-design.md#applicationtenant-mcp-integrations-and-agent-enablement); [remote profile](../../labnotes/20260905-0405-call-definition-design.md#initial-remote-protocol-and-input-validation--approved-r22r23); [R22–R26/R49](../call-definition-gap-review.md).

## Runnable outcome

A call's reception agent invokes one tenant-configured remote tool, continues speaking while it runs, receives the result, and explicitly updates permitted variables. Another agent/tenant cannot use that binding or its credentials.

## Specification

- Application/tenant integrations are configured infrastructure; each agent enables named operations through its unified local-key tools map. Tenant override replaces the whole integration record, not a deep merge. Calls carry no per-call MCP endpoint/credential override. Resolve tenant from trusted principal and pin bindings/catalog/schema/config generations in the call plan.
- Use the selected Jido MCP integration with MCP `2025-11-25` Streamable HTTP JSON/SSE responses, initialization/capability negotiation and scoped session handling. The earlier `2026-07-28` target is superseded. Do not advertise unsupported sampling/elicitation/tasks or silently negotiate an untested profile.
- Consume the separately verified thin `vxpipe_mcp` adapter around `jido_mcp` and expose
  enabled remote tools through the established Jido Action/Jido AI boundary.
  The integration owner supplies resolved configuration, private credentials, deadlines,
  pinned schemas and network policy; it owns tenant selection, grants, catalog scoping,
  call/agent lifecycle and result history. Neither gateway nor room processes implement
  another MCP parser. Jido MCP owns its protocol/client integration and transitive
  implementation choices; the internal adapter has no dependency on those domain
  applications and Vxpipe does not call a transitive client library directly.
- Auth variants are none, bearer, or validated custom headers; transport-owned headers cannot be overridden. Secrets stay in the private integration boundary, recoverable through configured secret storage, never tool arguments/plan projections. Authorization-scoped discovery/cache/health/concurrency state must not cross tenant/integration/credential generation.
- Follow Jido MCP and MCP SDK security guidance at Vxpipe's actual outbound boundary:
  trusted configured endpoints, verified HTTPS, address-at-connect/rebinding defenses, no
  automatic redirects/credential forwarding. Private destinations require explicit host
  permission, not tenant bypass. Revoked/invalid tenant credentials never fall back silently
  to application credentials.
- Use a real JSON Schema 2020-12 validator for actual outgoing tool arguments against pinned inputSchema, including required values; reject unsupported dialect/features/bindings before exposure and never fetch external refs automatically. Variable partial-population rules do not weaken MCP schemas.
- Enforce a configurable 1 MiB (1,048,576-byte) cumulative decoded/decompressed response limit incrementally, including streamed responses and resumption across HTTP responses. Preserve the invocation's absolute deadline and byte budget across progress/reconnects. Stop excessive receipt without asserting remote action failure or full archival. Accepted permitted responses archive fully; if too large for model context, return explicit projection omission, not chopped JSON or automatic summarization/retry.
- Reuse the application-level background execution contract. Results/linked resources are untrusted; preserve observed outcomes/descriptors, do not auto-fetch attachments or auto-map variables. Submitted timeout is unknown unless definitive evidence exists; no executor retries.

## Implementation checklist

- [ ] Red-test a controlled remote MCP fixture for discovery, valid tool invocation, slow result, schema failure, auth and response-size limits.
- [ ] Wire the verified Jido MCP adapter through the integration owner; preserve its pinned
  profile/conformance evidence and enforce dependency direction.
- [ ] Implement private scoped integration resolution/cache/discovery and Jido Action binding
  validation without unbounded external atom/module creation.
- [ ] Connect tools/call to background workers, complete private history, and safe model/client projections.
- [ ] Test security at the effective network client, not only a configured URL string; isolate real network interoperability tests.

## Acceptance and failure checks

- [ ] Tenant/app precedence is whole-record; bad/revoked tenant credentials do not fall back or leak to another endpoint/cache.
- [ ] Reject unknown/unauthorized tools, argument schema violations, unsafe redirects/private addresses/rebinding, external schema refs and unsupported interactions before unauthorized work.
- [ ] At/exceed the 1 MiB boundary with compressed and many-chunk bodies; no cap reset per chunk or full-body buffering before checking.
- [ ] Validate definite non-submission vs unknown submitted timeout; exactly one invocation, no automatic retries or implicit variables updates.
- [ ] Run while speaking; preserve live context and permitted archived result/descriptors; hidden client events remain hidden.
- [ ] Refresh/change a discovery catalog: existing calls retain pinned enabled schemas;
  new calls may resolve the new catalog, and unresolved enabled bindings fail preparation.
- [ ] Revocation fails closed instead of reusing stale authorization; private credential leases
  redact process status/crash output and are released/invalidated at room-incarnation end.
- [ ] Library invocation receives only scoped resolved inputs; domain authorization/history
  are tested here, protocol behavior in the library. Real integration uses that same client.

## Manual verification

1. Configure a synthetic remote service at tenant scope and enable one tool for reception only.
2. Create/join a call, invoke it, converse during its controlled delay, then ask the agent to save the result using a variable tool.
3. Repeat with another tenant, invalid args, timeout, and oversized response; inspect safe outcomes and permitted history.
4. Run the tagged HTTPS/streaming interoperability lane before claiming compatibility with a real configured MCP.

## Scope boundaries

No local/stdio MCP, per-call credentials, automatic retry/idempotency, explicit cancellation, late webhook reconciliation, OAuth onboarding, result/document fetching, or server-requested sampling/elicitation. Existing issue links describe deferred work, not dependencies.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added catalog/schema pinning, unresolved binding failure, revoked authorization and private lease redaction/lifetime tests; re-review approved.
The subsequent internal-library prerequisite and scoped-input/domain-ownership boundary
also passed milestone_review_a's focused follow-up review. The supported protocol revision
and non-resetting invocation bounds remain approved. The later Jido MCP mechanism selection
is user-approved but awaits an independent follow-up review.
This is specification evidence only; implementation and runtime verification remain unchecked.
