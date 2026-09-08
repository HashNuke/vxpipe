# Context compaction and supported LLM fallback

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Remote MCP](remote-mcp-tools.md); [Agent transfers](agent-transfers.md); [Usage/billing](usage-and-billing-observations.md).
Sources: [Approved context/provider boundaries](../../labnotes/20260905-0405-call-definition-design.md#provider-profiles-context-compaction-and-response-limits--approved-r47r50); [R47–R50](../call-definition-gap-review.md).

## Runnable outcome

A long agent conversation compacts older completed history before exhausting model input
capacity while preserving current work, variables and permissions. A configured
provider-native routing fallback supported by the selected Jido AI/ReqLLM provider surface
can be exercised without adding Vxpipe's own provider chain.

## Specification

- Before each conversational inference/tool continuation, measure all model input including instructions, tool definitions, transient variable projection, selected history and current work. Reserve output capacity; at75% of usable input budget compact older completed conversation toward below50%.
- Preserve instructions/tools, recent/current messages, unresolved invocation relationships and valid call/result pairing. Targets are not guaranteed if protected content is too large; never silently discard it or exceed model limit. Use a typed bounded failure when safe compaction cannot create room, rather than recursive/unbounded compaction attempts.
- Summarizer model/provider/execution selection remains unapproved. Before production requests, explicitly settle that narrow selection and record it; do not silently add a cheaper/new provider, local model, or broaden data recipients. A controlled fake compactor proves orchestration independently. Define concrete token accounting/safety margin and failure/deadline behavior without claiming exact counting for unsupported models.
- Compaction sees only agent-authorized conversation. Summary is derived untrusted data, not system policy, tool result or tool-execution authority. It never updates CallVariables/grants or replaces full permitted archival history. Derived transcripts retain source-interval storage restrictions.
- Snapshot-based work preserves messages/tool completions arriving afterward; stale results from terminated activations cannot attach to another agent. Keep bounded work outside RoomAuthority/media and attribute observed compaction usage without inventing a user turn or changing retention.
- Expose only provider-native/router fallback options supported through Jido AI's ReqLLM
  provider layer and existing configured profiles. No Vxpipe fallback schema/chain/
  coordinator and no new STT/TTS fallback. Preserve the same permissions/tools/privacy and
  actual observed provider/model usage. Provider-managed fallback is not permission to repeat
  an MCP action or replay already-emitted speech after a broken stream.

## Implementation checklist

- [ ] Red-test token-budget trigger/target with fake compactor and realistic tool/history/variable input envelopes.
- [ ] Resolve and document summarizer selection and token accounting/limits before authorizing its production data flow.
- [ ] Implement bounded summary work, protected-history replacement and late-message/activation checks.
- [ ] Preserve summary provenance/privacy and metered usage through existing event/storage boundaries.
- [ ] Validate/pass through supported native fallback options and add controlled plus tagged adapter interoperability coverage.

## Acceptance and failure checks

- [ ] Below/at75% trigger after output reserve and target below50%; protected oversized input fails safely without deletion or oversized request.
- [ ] In-flight tool acknowledgement/result links and new user/tool messages survive compaction; terminated-agent summary cannot leak into another activation.
- [ ] Inject instructions in history/result/summary: no tool execution or grant/variable mutation follows from summarization.
- [ ] Full permitted archive is intact; denied transcript summary is not stored; other-agent private history is not read.
- [ ] Native configured fallback preserves tools/schema/privacy and truthful actual model/usage; partial-stream failure doesn't resubmit tools or silently restart emitted speech.
- [ ] Timeout/error/malformed summary leaves original live context intact; merge intervening
  input/tool completions, then recheck budget before inference without dropping protected work.
- [ ] Compactor has no execution/tool authority; this is not a promise that later LLM reasoning
  is immune to adversarial text. Known unsupported native fallback/profile options fail validation.

## Manual verification

1. Use a low controlled context budget and fake compactor to reach the threshold during a conversation with a background tool.
2. Add input while compacting, then continue; inspect retained recent messages, variables and tool relationships.
3. Verify original permitted history versus derived model summary and observe compaction usage separately.
4. After approving summarizer selection, run its tagged integration and a supported native routing-fallback fixture; inspect safe partial-stream failure behavior.

## Scope boundaries

No Vxpipe-managed provider fallback chain, automatic tool retry, automatic oversized-result summarizer/document inspection, transfer-history summarization, newly approved summarizer provider, or local models. This milestone is not complete until its explicitly outstanding execution-model choice is settled and tested.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added failed/stale compaction preservation, merged-input budget rechecks, limited summarizer authority and unsupported fallback validation; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
