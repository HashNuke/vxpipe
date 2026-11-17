# Structured agent messages and append-only history

Status: all four checkpoints complete and independently reviewed, 2026-11-17.
Final verification passes 5,446 tests with zero failures and 387 exclusions
(seed 469087), all static/dependency gates and Lean. Configured idle and live
browser acceptance pass. See the [implementation labnote](../20261116-1642-implement-structured-messages.md). This is the
implementation owner for the [simple message-format design](../../docs/design/structured-agent-messages.md).
The milestone index owns implementation order. A reviewed document is not a
completed feature.

## Runnable outcome and prerequisites

A configured LLM agent distinguishes participant messages from platform input,
retains original native tool calls and their responses, and continues through
background tools without mutable pending-status context. Its final dialogue
responses are validated objects; only admitted response text reaches TTS.
Ordinary history messages preserve their serialized prefix. Existing dynamic
business context remains unchanged while call_state_changed is deferred.
An idle tool stops old speech, permits one optional acknowledgment, then waits
without blocking user input and triggers idle_timeout once if the wait expires.

Build on the completed [ReqLLM runtime](reqllm-agent-runtime.md),
[background tool conversation](background-tool-conversation.md),
[shared tool execution](shared-participant-tool-execution.md),
[Call Variables](call-variables-and-tool-visibility.md),
[context compaction](context-compaction-and-native-fallback.md) and configured
agent/service/publication paths. Those milestones' completed evidence stays
historical; this milestone owns the intentional message-projection changes.

Read the linked design and current RequestRunner, RequestProjection, Message,
Conversation, completion-continuation and provider-normalization boundaries.
AgentRuntime owns generic content/results and history. Call Engine owns speaker
attribution, admission, tool lifecycle and playback authority. Provider adapters
own wire roles, content encoding and native tool protocol.

The [voice behavior milestone](voice-agent-turns-and-listening.md) consumes this
protocol. Its classifier, precise TTS timing, listening cues and new interruption
policy are not prerequisites here. Use existing coarse playback evidence with
internal uncertainty; never wait for optional alignment. Native speech-to-speech
wire/media/tool protocols and the deferred Models-tab classifier control remain
outside scope. Shared behavioral prompt composition applies to STS agents too,
but the LLM-only structured dialogue contract does not.

## Approved contracts

| Concern | Required behavior |
| --- | --- |
| Roles | `user` is platform-supplied input, not proof that a human spoke. Participant content identifies its participant; platform events/results are explicitly typed. |
| Simple content | Participant messages use `type`, `participant_id`, `message`, `agent_mode`; proposed platform inputs use `type`, `event`, `data`, `agent_mode`. Freeze mode at initial input admission. Existing native tools and engine completion observations remain unchanged, without mode. No model-visible turn machinery, overlap/classifier diagnostics or playback metadata. |
| Native tool calls | Preserve the original assistant tool-call messages, IDs, arguments, accompanying protocol content and opaque provider metadata. Preserve their matching native responses. Do not flatten these into participant speech or discard them when execution completes. |
| Pending status | Remove extra pending inventories/snapshots from every model-input channel, including system and interruption prompts. No latest-only overlay, empty pending list or periodic status-update message. Runtime tracking remains. |
| Submission versus completion | Keep the current native running/rejected acknowledgment and the later engine-origin tool_invocation_completion observation, including its trust preamble and nested outcome. Neither gains mode or a replacement tool_result envelope. The later observation is not a second native result for the same call. |
| Append-only growth | New input, tool calls and responses append; previously committed messages do not change. Keep deterministic serialization. Context reset/compaction/privacy/configuration boundaries are explicit exceptions, not silent history rewrites. |
| Common model response | Exactly agent_mode (listener or speaker) and message (null or nonempty string). listener/null is no new output; listener/message is a cue; speaker/message is a main response; speaker/null is invalid. No interrupt_agent field. Runtime supplies identity/type in history; native tool rounds remain distinct. |
| Stop-and-wait | Native idle tool with bounded duration_seconds, e.g. 10, stops the eligible old output and permits its associated optional speaker acknowledgment. Start the quiet timer after that acknowledgment settles; otherwise after old output settles. No separate finish-old-then-reply action. |
| Control authority | Mode is output intent; runtime owns actual mode and exact-target cancellation. listener/null leaves existing playback alone; admitted speaker replacement or idle stops only its eligible target. A completed target needs no cancellation; a newer output is never stopped by a stale result. |
| Speech evidence | Settle supported spoken text before history commit. Generated output, zero/unknown distinctions, timing and corrections stay internal; no delivery object or speech_delivery/correction events go to the LLM. Late evidence only updates archive/UI projections. Precise word truncation belongs to voice. |
| Protocol instructions | Editable shared, LLM-dialogue and compactor sources compose automatically with authored instructions, package once and pin revisions. STS receives no LLM JSON overlay. Prompt covers native idle, idle_timeout, tools and summaries; native tool schemas stay separate. |
| Encoding | Encode all structured text payloads as JSON strings for text-content fields, including participant/platform/assistant/summary content. Preserve native tool blocks and already encoded strings without double encoding. Adapters own supported text-part/wire variations; output JSON is parsed and validated before TTS. |
| Fixed greeting | Given greeting text goes directly to TTS, with settled assistant speech retained in history and no LLM generation request. Existing explicitly generated greetings remain distinct; wait_for_input sends none. STS uses its native opening path. |
| Trust/privacy | The runtime supplies identity and real tool outcomes; external strings remain untrusted. Preserve permission-filtered variables, private bindings, retention and redaction through nested content. |

## Checkpoint outcomes and dependencies

| Checkpoint | Usable result | Prerequisite |
| --- | --- | --- |
| A — Attributed conversation content | A configured agent receives structured participant/platform input and truthful attributed history. | Existing runtime/configured call. |
| B — Tool conversations with stable history | A slow tool runs while unrelated conversation continues; original calls, native responses and later outcomes stay intact without pending snapshots. | A. |
| C — Validated replies and supported-profile activation | A configured LLM-plus-TTS call handles main-response/silence/cue intent, tools and recovery through validated mode/message results and shared prompts. | A/B; audible listening cues remain voice E. |
| D — Timed pauses and resumptions | A configured agent stops its prior response, optionally acknowledges, waits ten seconds while receiving input, then resumes once on input or idle_timeout. | C and existing native tool/room/output lifecycle. |

A may retain the existing final-response behavior while introducing input
projection; B retains it for the tool slice. They do not claim the full protocol
is enabled. C completes the selected-profile transition, with existing published
and running legacy profiles preserved. All four exits include real configured
behavior, not only structs or adapter fixtures.

For each runtime checkpoint use focused red-green-refactor tests, update relevant
docs/evidence and run `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix test`, and `mix deps.unlock --check-unused` from the root.
Speech/source state changes also require `bin/verify-lean`; UI changes require
rendered browser inspection. Provider network checks stay in the tagged lane
through `bin/livetests run`; never read or modify the prohibited provider env file.
Missing required acceptance keeps its checkpoint open. No deployment is implied.

## Checkpoint A — Attributed conversation content

**Exit:** capture the actual request of a configured agent after participant input
and a platform event; it preserves both meanings under the appropriate wire roles.

- [x] Write failing request-boundary tests for human speech/text, two participant
  identities, generated greeting/idle input and permitted prior agent content.
  Prove fixed greeting text reaches TTS with zero LLM rounds and correct settled
  history, including zero/partial playback; preserve wait_for_input/native openings.
  Use the design's idle_timeout transcript cases; call_state_changed is deferred. Prove
  a provider user role alone never creates a human utterance or public transcript.
  Cover both modes, queued input, input-admission capture, immutable replay/retry
  after mode changes, per-recipient agent projections and unknown legacy modes.
- [x] Implement the design's minimal typed content and provider projection without
  a new event bus or model-visible turn machinery. Include the design catalog's
  participant/platform/summary variants; freeze mode once only on participant
  and platform inputs. A participant cannot author that field. Preserve native exchanges and engine
  completion observations without mode or rewrapping. Mode alone is not overlap
  or authority. Exclude overlap/classifier/playback objects and delivery events;
  keep private correlations outside model content.
  Verify JSON-string encoding at the actual provider boundary for every new text
  payload, quotes/newlines/Unicode, no double encoding and preserved native blocks.
- [x] Own the basic listener/speaker lifecycle in Call Engine, scoped to activation
  and response generation. Capture input mode before its response admission;
  remain listener during response-decision evaluation and enter speaker only
  for validated main-response admission/TTS preparation. Return on matching
  settlement or cancellation/failure; listener/null leaves an existing main
  response alone. Cue intent does not itself overwrite active speaker mode. Test queued input, multiple sources
  and stale callbacks. Expose one mode source for later voice policy; no dependency
  on unfinished barge-in or cue implementation is allowed.
- [x] Preserve existing permitted Call Variables/transfer context and tools.
  Defer call_state_changed and cross-participant event publication. Keep stable
  prompt sources stable, but acknowledge that the current dynamic system suffix
  may change when business context changes; do not claim full-request prefix
  immutability. Rename only the new model notification to idle_timeout, for both
  call directions, preserving current timer eligibility and existing internal APIs.
- [x] Keep generated evidence separate from participant speech in projected history.
  Use existing completed-segment/coarse settlement. Test known-zero, unknown
  interrupted segments and valid model silence internally; retain only supported
  text in model history. No playback metadata or delivery events reach the LLM.
  Settle before committing the next ordinary request; late corrections belong to
  archive/UI projections and do not rewrite model history. No word-timing
  implementation or new alignment wait belongs here.
- [x] Test untrusted JSON-shaped speech, platform-looking tool data, malformed or
  oversized content and legacy messages with unknown attribution. Validate bounds
  and enforce runtime authority independently of model instructions.
- [x] Exercise transfer/recovery and compaction with typed content, preserving
  participant attribution, corrections/negation, commitments, unresolved questions
  and actual tool outcomes. Verify the separate compactor's retention instructions
  and main agent's summary interpretation; summaries contain no playback/pending
  diagnostics or invented facts. Nested retention filtering applies when transcript
  saving is disabled; current permissions govern projection and context reset.
- [x] Implement the [storage projection mapping](../../docs/design/agent-message-projections.md)
  across call_facts payloads, existing identity/order/source columns, history readers,
  inspection and immutable publication formats. Define trusted format/version
  decoding for legacy text versus structured content, avoid a blanket backfill,
  and add a migration only for a demonstrated column/index invariant. Test nested
  message/cue/summary retention and raw JSON redaction at both owning boundaries.
- [x] Update Console presentation/decoder, @vxpipe/core types/stores and
  @vxpipe/react conversation fixtures/stories together. Project display text and
  cue purpose; no control JSON, fake human events or empty speech bubbles. Preserve
  native tools and legacy histories, actual media state and spoken-range mapping.
  Verify live/published parity and inspect rendered browser views at relevant sizes.
- [x] Run a configured call/text session through the real projection with captured
  requests and permitted transcript inspection. Record the selected profile and
  observed coarse-delivery limits; pass the common checks before marking A done.

## Checkpoint B — Tool conversations with stable history

**Exit:** a configured agent starts a controlled slow tool, answers unrelated
input, and later uses its result once. Original call/result records remain intact.

- [x] Write failing sequence tests that retain the original assistant call ID,
  name, arguments, accompanying content and provider metadata. Capture native
  response pairing and the later async result; compare the already committed
  serialized prefix after each append, not only the in-memory object shape.
- [x] Remove additional pending-status projections from messages, system state
  and model-context sources. Preserve the InvocationRegistry, deadlines,
  blocking/non-blocking admission and current authorization. Extra inventory
  changes must not trigger requests or synthetic status messages. Preserve the
  existing native call/ack model-loop round and actual completion continuation.
- [x] Preserve the existing true submission-response contract for background
  work. An immutable native acknowledgment is a historical acceptance fact,
  never a fabricated final success. Preserve synchronous final native results;
  do not also append a duplicate application completion for the same outcome.
- [x] Append actual async outcomes through the existing serialized completion
  owner without changing ContinueAgent's original preamble/payload or adding mode.
  Preserve nested outcome and absent result for failed/unknown. Cover success,
  definite failure, unknown timeout and teardown semantics,
  several concurrent/out-of-order completions, completion during generation,
  recovery and duplicate delivery. No lost result, repeated side effect or stale
  source admission; a completion never rewrites an in-flight prompt.
- [x] Verify original native calls and matching responses survive interruption,
  subsequent input and completed execution. Preserve provider adjacency rules,
  tool IDs and opaque signatures. Never orphan a native response, insert a
  missing call into an old prefix or mutate a submission result into completion.
- [x] Verify existing duplicate-submission/retry controls without deduplicating
  unrelated calls by name or blocking legitimate later repeats. Pending knowledge
  stays in runtime policy; no extra snapshot is needed to maintain authority.
- [x] Run the slow-tool configured-call scenario and tagged real provider
  interoperability for the selected profile. Capture protocol evidence, retained
  call/result history and absence of extra pending state; pass the common checks.
  A profile unable to support the required background behavior remains unenabled.

## Checkpoint C — Validated replies and supported-profile activation

**Exit:** a configured LLM-plus-TTS call demonstrates structured speech and silence,
native tool rounds and a subsequent response after recovery, with clean history.

- [x] Write failing tests for the common agent_mode/message response,
  using one schema/decoder for ordinary, greeting, idle_timeout, tool-continuation
  and overlap replies. Cover listener/null, listener/cue, speaker/message,
  rejected speaker/null, operation-specific admission, and parser rejection of missing/extra/duplicate fields,
  wrong types/blank strings, refusals, incomplete streams and provider failure.
  A valid null result succeeds; a malformed result cannot masquerade as silence.
- [x] Add typed result normalization and schema enforcement for the selected
  provider, retaining native tool-call rounds and metadata as distinct results.
  The selected OpenAI Luna Responses profile uses one fixed native strict
  text.format schema with the full tool allowlist and strict runtime enforcement.
  Both Google candidates failed acceptance and remain unsupported for modern
  publications. Preserve bounded, scoped native reasoning replay independently
  of speech and reject unsupported layouts. Do not switch strategies per round.
  Load editable shared/LLM prompt sources, compose with authored call-spec
  content and test exact inclusion, tools/summary/idle guidance and schema.
  Expose one typed mode/message result for voice policy; mode is output intent,
  not a direct global-state write. Partial-input operations may propose listener
  cues when enabled, but no premature main reply. Before voice E is enabled,
  suppress/reject cue audio through explicit profile admission without taking
  the floor. There is no interrupt field or independent deferred-reply result. Do not wrap prose as a valid result
  or accept unsupported mixed result ordering.
- [x] Admit only fully validated response message to TTS; do not speak metadata,
  native tool-call prose or partial JSON. Bound buffering, request/repair deadlines
  and cancellation. Null speech settles the request without a fictional spoken
  exchange; admitted input and durable tool facts remain available.
- [x] Pin protocol selection through persisted configuration, compilation,
  publication, startup, transfer and recovery, including prompt-source revisions.
  Package prompt files without duplicate hard-coded copies; prove missing assets
  fail configuration and active prompts do not change on an edit. Automatically
  compose shared instructions for all agents and keep LLM-only instructions out
  of STS provider prompts; retain native wire/media/tool behavior. Preserve legacy running/published
  profiles explicitly; unsupported structured-output/tool combinations fail
  validation rather than silently downgrading.
  Existing sample installers may explicitly create a pinned legacy bundle through
  trusted host options to preserve their provider/credential examples. Normal saves
  default to the modern profile; failed modern validation never selects legacy.
  Existing revisions retain their stored protocol regardless of creation options.
- [x] Prove append-only behavior for ordinary input, native calls/results and
  asynchronous outcomes. Test existing dynamic-variable context as an explicit
  request-prefix exception while its new event is deferred. Test compaction,
  redaction/permission change and provider/configuration boundaries; preserve
  necessary call/result pairs and never invent attribution on legacy data.
- [x] Run a real configured browser call with speech, valid silence, a native tool
  exchange, async completion and later input. Inspect actual submitted messages,
  provider results and emitted audio. Verify no control JSON or pending snapshot
  is spoken/forwarded and no tool result is misattributed as human speech.
- [x] Measure first-audio latency and token cost for short/long replies and tool
  continuations, including complete-object validation. Check profile deadlines
  and report regressions; any incremental framing optimization needs a reviewed
  contract before activation. Record serialized prefix comparisons and actual
  cached input tokens where available, without claiming guaranteed cache hits.
  The broader voice milestone's one-second target is unchanged.
- [x] Record supported provider profiles, native protocol evidence, failure and
  recovery checks, migration notes and common gate results. Update progress/index
  per completed checkpoint; mark the whole milestone done only when A–D exits
  pass. Additional voice/provider/transport coverage remains
  in the voice milestone; specification review does not complete either milestone.

## Checkpoint D — Timed pauses and resumptions

**Exit:** in a configured LLM-plus-TTS call, “give me a moment” invokes idle,
optionally speaks a short acknowledgment, then waits while remaining responsive.
Ten seconds after acknowledgment settlement, one idle_timeout can trigger a
contextual follow-up; an earlier human reply cancels that timeout.

- [x] Write failing idle lifecycle tests for exact-target old-output cancellation,
  optional associated acknowledgment, speaker-to-listener settlement, timer start
  after playback, silent acknowledgment, early human input, expiry/cancel races,
  duplicate tool calls, source replacement and stale/newer-output callbacks.
- [x] Add the bounded native platform idle tool through the existing authorized
  tool/submission owner and room-owned control boundary. Use duration_seconds=10
  in acceptance, validate configured bounds and deadlines, and preserve original
  call/ack/completion formats. No sleeps in GenServer callbacks or blocking of human
  conversation. Permit only the associated acknowledgment during the armed hold;
  suppress unrelated cue/main output. Bound missing acknowledgment and sink failures.
- [x] Own pending/active idle timer state with existing supervision/correlation.
  Cancel on fresh user resumption, replacement/teardown or invalidation; do not
  mistake the admitted origin input for resumption. Suspend/rebase ordinary idle
  detection to avoid duplicate expiry. Settle actual completion and idle_timeout
  in one serialized model continuation; early cancellation creates no independent
  speaking request. Preserve completion history and exactly-once execution/expiry.
- [x] Wire idle availability, tool schema and prompt guidance through existing
  authoring/publication/permissions and pinned LLM profiles. It is an application
  control operation, not an unrestricted speculative business tool. Missing/disabled
  idle cannot be faked by returning listener/null. Keep STS native tool/control
  protocols unchanged; general STS idle support is outside this LLM slice.
- [x] Run configured-call acceptance with acknowledgment and silence, actual ten-
  second quiet timing measured from settled output, early reply, expiry once,
  background completion during the hold and an almost-finished old answer. Inspect
  the browser timeline and native tool history; no JSON speech or duplicate follow-
  up. Record focused/root/Lean and relevant provider evidence before completing D.

## Ownership and design review

Implementation evidence is recorded in the [checkpoint labnote](../20261116-1642-implement-structured-messages.md).
Checkpoint A is complete. Its ten tasks deliver structured admission/mode snapshots,
supported speech settlement, attributed transfer/summary history, packaged/pinned
shared and compactor instructions, versioned archive retention/readers and client
presentation. The full Astra xhigh review covered every A task, reproduced findings,
fixes, missing acceptance evidence and module/SRP/dependency placement; final
re-review has no remaining validated finding. Desktop/phone dark/light inspection
and persisted publication compatibility pass. Final root verification passes
5,358 tests, zero failures, 385 excluded (seed 739852), plus all static gates and Lean.
Workspace client tests (45) and Console frontend tests (1,142) pass. The linked labnote records
earlier failures and their corrections.

Checkpoint B is complete. Pending snapshots are excluded from provider payloads
and token estimates while private control state and native history remain intact.
Captured provider JSON and the configured slow-tool conversation preserve the
serialized message prefix, native acknowledgments and opaque signatures through
unrelated input and completion. Astra reviewed all seven task groups and owner
boundaries with no remaining validated finding. The tagged Gemini case passes
four real streamed rounds; final root verification passes 5,361 tests, zero
failures, 385 excluded (seed 352487), with all static gates. B changed no speech/
source state machine or interface.

Checkpoint C is complete. Strict mode/message results, native tool exchanges and
private reasoning replay are validated before speech. OpenAI Luna uses one native
Responses strict schema with its full tool allowlist; rejected modern Google
candidates remain unsupported while legacy publications keep their protocol.
Prompt bundles survive save/publication/preparation, transfer and a supervised
Session restart. Invalid replies produce no speech and later valid responses
reach TTS, PCM and matched settlement. The real Chrome call passes eight provider
rounds and seven speech/silence/tool cases; desktop and phone conversation views
are inspected. Measured first audio is 1.99–4.99 seconds, above the unchanged voice target;
pricing is unknown and cache observations carry no guarantee. Listener cues remain
suppressed until voice E. Full Astra xhigh source, evidence and owner review has no
remaining validated finding. Independent parser/protocol/replay checks (22/0) and dynamic
context wire check (1/0) pass. Checkpoint C root verification passed 5,403 tests, zero
failures, 387 excluded (seed 918318), all static/unused-lock gates and Lean. See the
implementation labnote for red/green, provider, browser and recovery evidence.
Checkpoint D and its independent Astra xhigh review are complete. Final current-source
verification passes 5,446 tests, zero failures and 387 exclusions (seed 469087),
formatting, compilation with warnings as errors, strict Credo, unused-dependency
checks and Lean (nine build jobs and one replay test). Configured cases cover
exact old-output cancellation, optional acknowledgment, early input and expiry
ordering, duplicate and successive waits, background completion retention,
source departure, connection replacement and transfer holds. Missing model
acknowledgment and failed/stalled playback are bounded by the thirty-second
arming deadline. Ordinary idle is suspended and rebased. A real Chrome call
with OpenAI and Deepgram passes fourteen model rounds, including spoken and
silent ten-second waits; actual expiry follows settlement by 10,006.8 ms and
10,001.2 ms respectively. Native history remains append-only. Desktop and phone
rendering were inspected. The review's transfer-hold finding is fixed and passes
independent configured verification. Detailed red/green and review evidence is
in the implementation labnote. The final umbrella rerun also passes the native
WebRTC handoff case that timed out in the preceding run; it needed no behavior
or timeout change.

All thirty task groups and the milestone index entry are now checked. The
separate voice-behavior milestone remains responsible for classifier integration,
precise TTS alignment, speculative overlap and audible listener cues.

| Former generic work in the voice plan | New owner |
| --- | --- |
| A's attributed content/history task | A's typed projection, coarse delivery and configured-session checks. |
| C's ordinary/platform input construction | A; voice C reuses it while retaining overlap/classifier evidence internally. |
| C's removal of pending state and prefix checks | B; C checks context boundaries and actual cache evidence. |
| C's generic native tool/result retention and async completion | B, preserving original messages and genuine submission responses. |
| C's generic result validation and raw-delta/TTS admission | C; voice C consumes the type and applies overlap authority. |
| C's protocol publication/legacy/recovery checks | C, with typed content recovery introduced in A. |
| F's generic provider/prefix/cache checks | C; voice F keeps the broader combined transport/language regression matrix. |

This document owns the generic format, native tool retention, removal of pending
snapshots, append-only projection, typed final result and protocol compatibility.
It replaces the generic format tasks previously embedded in voice checkpoints
A/C/F. Voice A/B own precise spoken-word evidence; voice C owns overlap decisions,
cue-window/mode policy and actual cancellation/admission; voice F owns the combined
transport/language matrix. Each tests its own boundary using this protocol.

### Historical specification reviews

The following records describe design decisions and task status before implementation.
Current completion evidence is recorded above.

Local dependency review keeps this milestone independent of unfinished classifier,
cue and timing work. The first three checkpoints deliver attributed conversation,
working background tools and a validated speaking agent; D adds timed pauses. Preserving
original calls and genuine submission responses resolves the ambiguity in the
earlier phrase “only responses”; only additional pending snapshots are removed.
Independent Astra xhigh review of this extraction found no material findings.
It confirmed retained native calls/submission responses, complete task ownership,
acyclic dependencies and three configured-agent exits. At that review, all 22
tasks remained open.

The user then requested one common reply envelope with `interrupt_agent` and
`agent_mode` on messages sent to the agent, followed by a complete variation
catalog for review. A/C now cover frozen mode context and the same type/text/
interrupt_agent schema for all dialogue. A owns the basic mode lifecycle to avoid
a dependency on voice C;
voice C consumes it for cue/overlap policy. There are now 23 open tasks.
Independent Astra xhigh review of this amendment identified missing explicit
zero/unknown delivery examples. The catalog and A acceptance now cover them,
including their distinction from valid model silence. Re-review found no material
findings and confirmed mode ownership and dependency order.
The user's subsequent simplification supersedes that larger catalog: playback
and classifier details stay internal, delivery events are removed, and original
completion messages retain their current structure without mode. Existing A/B/C
tasks now cover these exclusions and explicit main/compactor system instructions;
the task count remains 23, all open. Source verification and the current review
are recorded in the [question labnote](../20261116-1107-message-format-questions.md).
Independent Astra xhigh review found no material findings; it confirmed the
source-backed triggers/tool encodings, exclusions, task ownership and acyclic
dependencies. Clarified mode scope and preserved acknowledgment continuations.
The next user review adds direct-TTS fixed greeting checks, concrete idle/state
transcripts, explicit text-content encoding and editable shared/LLM/compactor
prompt sources. Existing tasks A/C cover these without adding checkpoints; all
23 tasks remain open. Assistant-mode replacement is an open behavior decision,
not an approved removal of the existing deferred-reply outcome. See the
[prompt-contract labnote](../20261116-1534-agent-prompt-contract.md) for review.
Independent Astra xhigh focused review found no material findings in the source
examples, encoding, shared/LLM/compactor ownership or existing task coverage.
The assistant-mode behavior decision remains open and is not approved by review.
No implementation, browser, provider, latency or cache acceptance is claimed.

The later mode/idle clarification supersedes the earlier four-result control
contract and open mode-only question. Final dialogue is agent_mode/message;
explicit idle owns stop-and-wait plus optional speaker acknowledgment. idle_timeout
replaces the proposed caller_idle name; call_state_changed is deferred with current
variable access preserved. Two new A tasks own storage/JS projection, and five D
tasks deliver the new idle vertical slice: A10/B7/C8/D5, all 30 tasks open. Voice C
requires D for the explicit idle overlap path; no new implementation is claimed.

Independent Astra xhigh review of this latest amendment found no material
findings. It checked source-backed greeting/storage/viewer claims, scoped idle
acknowledgment, timer/completion coalescing, early-input cancellation, cue gating,
exact-target stale-result protection and acyclic dependencies. It independently
confirmed A10/B7/C8/D5 = 30 open tasks and valid JSON examples; one stale text:null
label was corrected to listener/message:null. Implementation acceptance remains open.
