# Context compaction and supported LLM fallback

Status: complete. Long conversations now use bounded, private context
compaction without changing tool or variable authority. Supported
provider-native routing options pass through the pinned model profile with
truthful routed-model usage; Vxpipe adds no provider chain. Focused, full-suite,
tagged-provider, HTTPS/WebRTC, and responsive browser evidence is recorded
below. The guarded live Zenmux check remains unrun because its credential is not
configured. Specification review: approved (2026-09-08).
Prerequisites: [Remote MCP](remote-mcp-tools.md); [Agent transfers](agent-transfers.md); [Usage/billing](usage-and-billing-observations.md).
Sources: [Approved context/provider boundaries](../20260905-0405-call-definition-design.md#provider-profiles-context-compaction-and-response-limits--approved-r47r50); [R47–R50](../20260906-1452-call-spec-gap-review.md).

## Runnable outcome

A long agent conversation compacts older completed history before exhausting model input
capacity while preserving current work, variables and permissions. A configured
provider-native routing fallback supported by the selected ReqLLM provider surface
can be exercised without adding Vxpipe's own provider chain.

## Specification

- Before each conversational inference/tool continuation, measure all model input including instructions, tool definitions, transient variable projection, selected history and current work. Reserve output capacity; at 75% of usable input budget compact older completed conversation toward below 50%.
- Preserve instructions/tools, recent/current messages, unresolved invocation relationships and valid call/result pairing. Targets are not guaranteed if protected content is too large; never silently discard it or exceed model limit. Use a typed bounded failure when safe compaction cannot create room, rather than recursive/unbounded compaction attempts.
- Production summary work reuses the active activation's pinned model/provider/credential and validated provider-native routing options in one bounded, buffered, tool-less request. It does not select a cheaper/new provider or local model, broaden data recipients, or expose execution tools. A controlled fake compactor proves orchestration independently. Concrete conservative accounting, safety margins, and deadlines apply without claiming exact tokenizer parity.
- Compaction sees only agent-authorized conversation. Summary is derived untrusted data, not system policy, tool result or tool-execution authority. It never updates CallVariables/grants or replaces full permitted archival history. Keep it private to the Agent Runtime Session and subsequent model requests; never publish it to clients or storage.
- Snapshot-based work preserves messages/tool completions arriving afterward; stale results from terminated activations cannot attach to another agent. Keep bounded work outside RoomAuthority/media and attribute observed compaction usage without inventing a user turn or changing retention.
- Expose only provider-native/router fallback options supported through the agent runtime's
  ReqLLM provider layer and existing configured profiles. No Vxpipe fallback schema/chain/
  coordinator and no new STT/TTS fallback. Preserve the same permissions/tools/privacy and
  actual observed provider/model usage. Provider-managed fallback is not permission to repeat
  an MCP action or replay already-emitted speech after a broken stream.

## Implementation checklist

- [x] Red-test token-budget trigger/target with fake compactor and realistic tool/history/variable input envelopes.
- [x] Resolve and document summarizer selection and token accounting/limits before authorizing its production data flow.
- [x] Implement bounded summary work, protected-history replacement and late-message/activation checks.
- [x] Preserve summary provenance/privacy and metered usage through existing event/storage boundaries.
- [x] Validate/pass through supported native fallback options and add controlled plus tagged adapter interoperability coverage.

## Acceptance and failure checks

- [x] Below/at75% trigger after output reserve and target below50%; protected oversized input fails safely without deletion or oversized request.
- [x] In-flight tool acknowledgement/result links and new user/tool messages survive compaction; terminated-agent summary cannot leak into another activation.
- [x] Inject instructions in history/result/summary: no tool execution or grant/variable mutation follows from summarization.
- [x] Full permitted archive is intact; denied transcript summary is not stored; other-agent private history is not read.
- [x] Native configured fallback preserves tools/schema/privacy and truthful actual model/usage; partial-stream failure doesn't resubmit tools or silently restart emitted speech.
- [x] Timeout/error/malformed summary leaves original live context intact; merge intervening
  input/tool completions, then recheck budget before inference without dropping protected work.
- [x] Compactor has no execution/tool authority; this is not a promise that later LLM reasoning
  is immune to adversarial text. Known unsupported native fallback/profile options fail validation.

## Manual verification

1. Use a low controlled context budget and fake compactor to reach the threshold during a conversation with a background tool.
2. Add input while compacting, then continue; inspect retained recent messages, variables and tool relationships.
3. Verify original permitted history versus derived model summary and observe compaction usage separately.
4. After approving summarizer selection, run its tagged integration and a supported native routing-fallback fixture; inspect safe partial-stream failure behavior.

## Scope boundaries

No Vxpipe-managed provider fallback chain, automatic tool retry, automatic oversized-result summarizer/document inspection, transfer-history summarization, separate summarizer provider, or local models.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: the first budget checkpoint reserves output before
deriving the input budget, triggers at the 75% threshold, targets strictly below
50%, and gives a bounded counter the complete normalized model request. Focused
tests cover threshold rounding, invalid windows/counts, realistic message/tool/
pending-variable envelopes, and counter failure. Protected-history tests cover
permanent/recent/pending-tool retention, whole-entry selection, late-entry merge,
durable-correlation preservation, derived-summary authority, and stale rejection.
A controlled fake compactor now receives only selected messages and their source
correlations, performs one bounded attempt, and has its complete rebuilt request
remeasured. Tests prove no invocation below threshold, protected-input failure,
failed compaction preservation, strict achievable targets, and unchanged full
request tools/pending/variable projection. Production summarizer/counter selection
now reuses the activation's pinned model/provider/routing state in a buffered,
tool-less request. Conservative encoded-byte accounting includes every normalized
input class and explicit envelope margins; context/output limits come from the
validated ReqLLM model/options. Unsupported native options fail configuration,
while a supported Zenmux routing policy passes through unchanged. See
[model-context compaction](../../docs/context-compaction.md). The Session now prepares and
commits a safe summary before every
inference/tool-continuation round, and terminating it kills blocked compaction
work. Call Engine passes its application setting into every agent activation. A
room-level test proves caller input explicitly queued during a blocked summary
request runs afterward using the committed compacted history; the ordinary
immediate-input path correctly remains an interruption. Derived summaries stay
inside Session/model context and are never published to clients or storage. The
runtime emits only bounded compaction usage/provider metadata and outcome; Call
Engine records it as a distinct model attempt on the triggering real turn, with
`context_compaction_` components. Rejected summaries retain known usage, and an
attempt without reported measurements retains a failed operation. The room
archive test proves original permitted input/output facts remain while the
summary sentinel never reaches an archive payload.
The ReqLLM boundary now has a controlled Zenmux-adapter request proving that one
request carries the configured native routing/fallback object, the exact
model-visible tool schema, and no private executor correlation. Its normalized
response retains the actual model and reported usage. A partial-stream failure
test proves that emitted text is followed by one typed failed result without a
second model stream, buffered generation, or tool submission. A separately
tagged live Zenmux test exercises the same native routing and exact schema when
`ZENMUX_API_KEY` is available; it compiles under the default excluded lane but
has not been run against the provider because that credential is not configured.
The resolved model capability profile may now add `generation_options` alongside
its model. Those options override matching application defaults while the
application retains credentials and runtime-only provider settings. The selected
ReqLLM adapter validates the merged configuration before room startup; a known
unsupported model/provider option combination rejects the call plan. Profiles
accept only recursively data-valued generation settings, and profiles without
generation options preserve the prior provider constructor contract.
Acceptance hardening directly covers compactor timeout and malformed-return
termination without changing the original conversation. Snapshot application
retains a complete tool-call/result exchange appended after selection, while the
existing pending-tool protection, queued-caller remeasurement, and Session-owned
worker termination prove that current work survives and a terminated activation
cannot publish or attach a stale result.

Final acceptance used the focused Agent Runtime compaction/routing suite (34
tests) and focused Call Engine integration suite (19 tests), both with zero
failures. The exact tagged Gemini transfer-schema interoperability check and the
Call Engine transfer-focused suite also pass after flattening the mixed transfer
schema exposed by the live replay. The Phoenix assets typecheck/build succeeds,
all seven Vitest checks pass, and the PostgreSQL-backed umbrella `mix test`
exits successfully with every default child suite green. Root formatting,
warnings-as-errors compilation, strict Credo over 802 source files, and unused
dependency checks pass.

An unmodified RTVI 1.13.0 client reached READY over the default HTTPS/WebRTC
development stack, completed ordinary typed text/audio, and projected the mixed
human-transfer function call plus the agent's hold/recovery responses. Desktop
and 390 x 844 mobile rendering have no horizontal overflow. Existing
third-party console accessibility findings and the sample shell's missing page
heading are retained as an explicit
[review issue](../issues/sample-voice-ui-accessibility.md), not concealed as
milestone success. This no-database development run could not admit the separate
human destination, so it does not replace the database-backed transfer proof
already recorded by the owning milestone.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added failed/stale compaction preservation, merged-input budget rechecks, limited summarizer authority and unsupported fallback validation; re-review approved.
This is specification evidence only; implementation and runtime verification remain unchecked.
