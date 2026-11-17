# Voice agent turns, listening cues and spoken transcripts

Status: consolidated specification, 2026-11-16; checkpoints A–F are unimplemented.
This is the single implementation checklist for TTS timing, contextual barge-in,
the CPU classifier and agent listening cues. Earlier milestone files redirect
here and retain historical evidence. The milestone index owns overall order.

## Runnable outcome and prerequisites

An LLM-plus-TTS voice agent preserves generated output separately from what
played, continues speaking through human acknowledgments, handles intentional
interruptions, and can emit brief listening cues while the human continues.
Provider timing and the CPU classifier are optional capabilities; local VAD
remains off by default. Native speech-to-speech behavior remains separate.

Build on completed [speech integrations](simpler-speech-integrations.md),
[provider packages](provider-integration-packages.md),
[persistent sessions](persistent-speech-sessions.md),
[transcript start/optional VAD](transcript-start-and-optional-vad.md),
[archive foundations](asynchronous-call-history.md) and existing configured
agent/service/publication paths. Reuse implemented playback/cache primitives
from [participant wait sounds](transfer-readiness-and-wait-sounds.md); unfinished
carrier acceptance there is not a prerequisite. General packaging, guardrail,
onboarding and debug-console UI milestones do not gate these checkpoints.

The [message-format milestone](structured-agent-messages.md) now owns generic
attributed content, retained native calls/results, pending-snapshot removal and
validated replies. Its A supplies the history boundary for voice A; its C supplies
the configured protocol for voice C. It does not depend on this voice milestone.
Use its coarse settlement first; word timing and new interruption policy stay here.

Read these specifications before the owning checkpoint:

- [TTS timing and spoken transcripts](../../docs/design/tts-playback-transcripts.md).
- [Classifier and structured interruption](../../docs/design/barge-in-classifier.md).
- [Agent listening cues](../../docs/design/agent-backchannel-responses.md).
- [Delivery/dependency review](../../docs/design/voice-conversation-iterations.md).
- [Structured agent messages](../../docs/design/structured-agent-messages.md).
- [Speech runtime](../../docs/en/development/speech-runtime.md) and
  [testing/Lean guidance](../../docs/en/development/testing.md).

The completed [Scribe wait-removal checkpoint](provider-turn-detection-and-contextual-barge-in.md#scoped-checkpoint--remove-scribes-local-endpoint-wait)
is existing baseline evidence, not completion of a new checkpoint. Preserve its
provider-gap semantics and optional local fallback. The broader **1,000 ms**
ordinary-response target remains an acceptance gate in F.

## Checkpoint outcomes and dependencies

| Checkpoint | Usable result | Pending prerequisite |
| --- | --- | --- |
| A — ElevenLabs interrupted transcripts | Generated `x y z` remains retained; supported spoken prefix `x y` is used by transcripts and the next model request. | Message-format A; use current interruption. |
| B — Rime interrupted transcripts | The same call behavior works with Rime's estimated timing and truthful uncertainty. | A's shared timing/history contract. |
| C — Structured interruption and modes | The shared message protocol drives acknowledgment, interruption and mode/purpose handling. | Message-format C/D and shared history projection; precise TTS timing is optional. |
| D — CPU backchannel filter | A real shared classifier avoids unnecessary LLM requests in a configured call, with validated fallback. | C for the selected profile. |
| E — Transcript-driven listening cues | A configured call produces useful acknowledgments with local VAD off and continuous human input. | C's mode/purpose boundary and E's experiment quality gate. |
| F — Telephone calls and language coverage | The combined behavior works across declared providers, languages, transports and resource profiles. | A–E for the declared supported profiles. |

A can ship without C/D/E. C need not wait for B or a timing-capable provider:
implement/reuse the shared coarse unknown-delivery projection if timing is absent.
E's replay/listening experiment can start immediately; its runtime activation
does not depend on D or TTS word alignment. Research and component commits sit
inside a useful checkpoint; they are not standalone checkpoint completions.

Each checkpoint includes its focused red-green tests, configured/manual evidence,
relevant documentation and root completion checks. For runtime/dependency work,
run `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix test`, and `mix deps.unlock --check-unused`.
Speech/source state changes also require `bin/verify-lean`, with new races covered
by the relevant models/replays. Any resulting UI requires rendered browser checks.
Use tagged live-provider tests through `bin/livetests run`; never read or modify
the prohibited provider environment file. A missing required acceptance result
keeps its checkpoint open. No checkpoint or review authorizes deployment.

## Checkpoint A — ElevenLabs interrupted transcripts

**Exit:** one actual configured browser call and its next response demonstrate
generated-versus-spoken history through the existing interruption path.

- [ ] Write the failing `x y z` -> `x y` test across playback, transcript, archive
  and next-model input. Retain generated `x y z` under the configured retention
  policy; record interruption and evidence provenance beside the spoken prefix.
- [ ] Add the optional typed alignment capability and bounded revision event at
  the integration boundary. Normalize text spans, half-open UTF-8 byte offsets,
  character/word granularity, rendered/original text basis, milliseconds and
  chunk/context/segment clock origins before participant consumption.
- [ ] Carry exact tenant/room/incarnation/activation/allocation/request/output
  generation and segment identities; validate finite ordered spans, Unicode
  boundaries, coverage and revisions. Duplicate, malformed and retired events
  cannot append text or mutate newer output. Apply normal speech-channel authority.
- [ ] Enable and verify alignment on the integrated ElevenLabs TTS profile.
  Test actual frame shape, normalized numbers, SSML, chunk boundaries and clock
  resets. Derive language-appropriate words without assuming spaces universally.
- [ ] Combine timing with the final supported playback cutoff at acknowledged
  cancellation. Preserve prior completed segments, omit queued suffixes and
  cut only at complete-word ends. Test exact-boundary, mid-word, silence and zero
  cutoffs, and audio progressing between human onset and completed cancellation.
- [ ] Preserve timing quality and playback evidence independently. Local sink
  delivery/egress is not remote hearing; cleared buffers/marks are not proof of
  playback. Scope evidence to the intended listener when recipients differ.
- [ ] Implement ordered spoken-turn replacement and the next LLM conversation
  projection once by correlation. Preserve original human input and durable
  tool facts; do not replay tools or keep an unplayed suffix as ordinary history.
  Settle spoken text before model-history commit. Late alignment may revise
  archive/UI transcripts only. Do not send playback metadata or delivery/correction
  events to the LLM, or rewrite a committed model message/in-flight prompt.
- [ ] Retain actually generated text, including unfinished buffered sentences,
  with complete/incomplete status when cancellation stops generation. Do not
  continue generation to obtain an unspoken suffix. Respect archive availability
  and retention filters for new nested timing/text/revision payloads.
- [ ] Keep unsupported/no-timing providers usable. Unknown delivery is distinct
  from known zero; completed segments retain their coarse delivery evidence.
  Bad/missing/late timing never delays playback, cancellation or the next turn,
  and never triggers synthetic proportional timings or another model/STT call.
- [ ] Exercise transfer, recovery and compaction of the new history projection,
  plus source/output replacement and transcript-saving-disabled behavior.
- [ ] Compare recorded browser audio, timestamp-derived cutoff, spoken transcript
  and captured subsequent model input in a configured ElevenLabs call. Report
  mapping error and missing playback evidence, then pass the common gates.

## Checkpoint B — Rime interrupted transcripts

**Exit:** a configured Rime call uses the same projection without provider-specific
participant logic or an implied endpoint migration.

- [ ] Write fixtures and conformance tests for the integrated Coda `/ws3` word
  timestamps, synthesis-batch origins, seconds conversion, context correlation
  and language/request timing absence. Preserve `provider_estimate` quality;
  do not advertise newer Coda completion alignment as this endpoint's behavior.
- [ ] Connect the adapter to A's common alignment/history path, including partial
  coverage, corrections, multiple synthesis batches and unavailable evidence.
  Confirm `x y z` -> estimated `x y` remains distinguishable from exact alignment.
- [ ] Run a recorded configured Rime browser call and its subsequent response;
  compare estimated cutoff with playback and verify missing timing cannot stall
  speech, fail the call or invoke an extra inference service.
- [ ] Verify the provider addition preserves A's no-timing, retention, Unicode,
  history ordering and retired-event contracts. Pass the common gates and record
  the supported model/language profile and measured estimate limitations.

## Checkpoint C — Structured interruption and participant modes

**Exit:** one pinned LLM-plus-TTS profile uses the shared message protocol to
distinguish acknowledgment from interruption without the CPU classifier in a
real configured call.

- [ ] Inventory and pin the selected STT/LLM/TTS profile's onset, replacement
  transcript, final-segment, endpoint, eager/resume and cancellation semantics.
  Record rejected alternatives and supported room/provider ownership. Preserve
  current native STS behavior rather than masking upstream automatic cutoffs.
- [ ] Separate speech activity/transcript publication from interruption admission.
  Require permitted human input and real interruptible main-output overlap;
  generation alone, typed text, listening cues, protected openings, briefing and
  hold/transfer are not equivalent overlap. Keep audio running during decisions.
- [ ] Implement bounded asynchronous decisions beside active LLM generation,
  using a read-only versioned snapshot and configured agent model/instructions.
  Do not wait behind the ordinary response queue or mutate history to obtain
  a snapshot. Keep semantic policy supervised apart from the LLM/tools/MCP group.
- [ ] Consume the message-format milestone's minimal attributed participant input
  and frozen `agent_mode`, with stable protocol instructions. Keep overlap,
  classifier scores/bypass reasons and playback evidence internal; do not add
  agent_output/classifier objects or delivery events to LLM input. Retain original
  tool calls/results and completion observations without mode or pending snapshots.
  Test semantic decisions with this smaller input and validate current applicability
  internally. Test untrusted speech/source attribution without a second projector.
- [ ] Consume the shared agent_mode/message response and native idle tool proposal.
  listener/null leaves old output running; listener/message requests a gated cue;
  speaker/message requests a main response. A speaker replacement or admitted idle
  call stops only the exact eligible target. No interrupt flag or separate deferred-
  reply action. Decode speculative idle calls without execution; admit this narrow
  control through the room and existing tool owner after current-source validation.
  Other speculative business tools remain forbidden. No raw JSON/prose reaches TTS.
- [ ] Test silence/ignore, listener cue intent, main reply and explicit idle with
  optional acknowledgment. Cover old audio finishing during model latency: stop
  becomes a no-op, while newer output cannot be stopped or relabelled. Keep actual
  runtime mode separate from requested output mode; no nearly-finished threshold.
- [ ] For partial human input allow only gated listener cue/no-output decisions
  or a validated early idle stop proposal, never a premature main answer. At final
  endpoint evaluate once even if text is unchanged. Preserve revised transcripts,
  acknowledgment-to-correction transitions and stop/wait requests; no duplicate
  final dispatch, tool side effect or idle_timeout. Idle acknowledgment waits for
  appropriate input admission and its timer starts after that acknowledgment settles.
- [ ] Bound candidates, per-participant/node concurrency, revisions, sizes and
  absolute deadlines. Capture exact source/policy/output/snapshot identities;
  reject stale results and authorize cancellation in the room. A finished target
  may still admit input, but a late result cannot cancel a newer response.
- [ ] Apply bounded snapshot-conflict reevaluation without retrying on every
  playback-progress update. For decision failure permit one bounded latest-
  revision retry, then retain completed input for ordinary handling after output
  settles. Expose failure; never classify failed work as a backchannel or invent
  a stop. Preserve received input through recovery and teardown boundaries.
- [ ] Settle cancellation and spoken history before the single owner commits an
  admitted user/assistant exchange. Reuse A's projection when present; otherwise
  use the same boundary with internal unknown-delivery handling. Preserve intervening
  tool commits and keep ignored speech in permitted evidence without triggering
  an answer or injecting it into ordinary conversation history.
- [ ] Consume the message milestone's activation/response-scoped mode lifecycle.
  Confirmed human endpoint closes its cue window even when no answer is admitted;
  no-speech settlement and old output callbacks cannot reopen a closed cue window.
  Add voice-policy integration checks without creating a second mode owner.
- [ ] Add exact output purpose/identity admission and settlement, separate from
  media visibility scope. A synthetic listening cue cannot cause barge-in
  evaluation or finish the human turn. Cue completion cannot switch mode; a new
  main response cancels the old cue with bounded acknowledged settlement.
- [ ] Test eager/resume as provisional, unrelated speakers, pending earlier real
  overlap, human input during generation, late cue/main callbacks and valid
  interruption after the original output ends. Resume requires fresh cue evidence.
- [ ] Distinguish retained original overlap from new substantive words arriving
  after playback ends without fresh overlap. An acknowledgment that merely ends
  late retains its provenance; a substantive continuation follows ordinary input
  admission instead of being suppressed by the earlier acknowledgment decision.
- [ ] Dispatch immediately on the selected provider's confirmed endpoint without
  an extra settling timer; keep committed segments/forced segments distinct.
  Retain bounded local/Silero fallback with renewed-speech cancellation, and
  prove optional VAD does not add another wait to provider endpoint handling.
- [ ] Pin semantic policy and preserve old published/running policy compatibility
  through existing DB-configured services. Test missing/late final text, duplicate
  endpoints, source replacement, permissions, hold/transfer and recovery.
- [ ] Demonstrate ignored acknowledgment, early/ordinary answer, correction,
  stop-and-listen, platform-triggered continuation, failure fallback and one
  subsequent response in a configured browser call. Inspect the actual typed
  requests and validated results. Measure decision/stop latency and extra LLM
  usage; pass common gates. Broader language/transport and the one-second target
  remain in F.

## Checkpoint D — CPU backchannel filter in configured calls

**Exit:** the same semantic call uses a real resident ONNX classifier for one
validated language/profile; accepted backchannels avoid an LLM request.

- [ ] Freeze the first language/profile and fresh tuning/acceptance sets, with
  false-suppression, missed-interruption and latency thresholds before tuning.
  Treat release scores/languages as model evidence, not production validation.
- [ ] Pin immutable HF revision, artifact hashes, labels, cleaner/tokenizer
  contract, runtime dependencies and license/NOTICE. Verify byte integrity and
  Python/Elixir cleaner, token IDs/masks, logits and probabilities with golden
  fixtures; reject corrupt artifacts/LFS pointers and unsupported graph/runtime.
- [ ] Expose and verify native per-session intra/inter-op threads, sequential
  execution and spinning controls through a reviewed binding extension/revision;
  assess dirty-CPU versus existing dirty-I/O scheduling and
  shared Ortex/Silero regressions. Start one worker/one intra-op thread on one vCPU;
  BEAM scheduler flags are not ONNX thread control. Measure cold load, warm cost
  and RSS before increasing sessions or sharing them. Use batch one initially.
- [ ] Build the named supervised node-local dispatcher/workers and small
  participant policy. Use bounded asynchronous fair admission, one running plus
  one coalesced latest revision, deadlines and explicit unavailable outcomes.
  Outages must not restart rooms/agent/tools or make call readiness wait on model
  readiness. Policy recovery rebinds fresh state and invalidates old decisions.
- [ ] Bound raw bytes/preprocessing as well as tokens. More than 64 model tokens
  bypasses filtering; do not truncate away a correction or invent a sliding-window
  input contract. Meaningful original text cleaned to empty also bypasses; empty
  activity cannot fabricate a model request. Reject nonfinite/invalid logits.
- [ ] Filter only authorized main-output overlap. Accepted backchannels continue
  audio and skip the LLM; all other usable text goes to C. Reevaluate changed
  text/final revisions; after an accepted stop bypass filtering for the rest of
  that human turn. Test known early-answer phases, ambiguous identical words and
  C's substantive post-playback continuation with an earlier accepted backchannel.
- [ ] Prove disabled/unsupported language, missing model, timeout, overload,
  invalid result and worker loss take C's fallback only for currently authorized
  eligible input. Source/activation replacement instead invalidates retired work:
  test no stale LLM submission, suppression, cancellation or response admission.
  Cancellation removes queued work; native work already running stays charged
  against capacity until it finishes, even after a BEAM timeout/cancel.
- [ ] Configure the intersection of declared, deployment-validated and participant
  enabled languages. Pin configured STT language/validated sets, including
  unknown/mixed-language bypass and reviewed regional mappings; never infer
  language from TTS voice, prompt or the classifier's short text.
- [ ] Persist default-on preference for newly added agents and explicit off,
  through inheritance, publication, prepare/join/restart/transfer. Effective use
  remains LLM-plus-TTS/language/readiness gated; STS remains valid. Keep global
  artifact/capacity settings separate from participant enablement.
- [ ] At implementation promotion create the deferred Agent properties sidebar
  -> Models disable-toggle, propagation and rendered-browser tasks. Record their
  scope without implementing the UI in this planning checkpoint; the runtime
  preference/fallback is testable through existing authoring APIs.
- [ ] Fetch and verify artifacts at build time into ignored external build cache;
  package only needed INT8/tokenizer/metadata/license files and provenance. Never
  commit weights/tokenizers/model Git history or download on startup/call admission.
  Verify offline image load/warm, optional source/embedded provision and readiness
  fallback. Pin live policies across upgrades; no uncoordinated model hot swap.
- [ ] Shadow-evaluate, then compare enabled/disabled filtering in a recorded
  configured call. Report service/queue/tokenization/inference/LLM/stop latency,
  LLM calls avoided, suppression errors, CPU/RSS and overload. Treat the proposed
  50 ms filter budget as a measured hypothesis, not a proven bound. Pass common
  gates; general distribution/publishing is outside this checkpoint.

## Checkpoint E — Transcript-driven listening cues

**Exit:** one validated language/voice profile in an opt-in configured browser
call produces useful audible cues, preserves human speech and answers once.
The experiment tasks below can begin before A–D; runtime activation requires C.

- [ ] Build replay/listening evaluation from recorded human audio and real ASR
  replacement/segment/endpoint traces, preserving source and reception/audio
  clocks. Compare no cue, progress/cadence and bounded semantic `phrase_id|null`
  selection on the same inputs with local VAD off. phrase_id is a comparison
  baseline; production semantic cue candidates use the common listener/message
  result and bounded configured model access, with no business tools or ordinary-
  history mutation. Avoid a second mandatory cue response schema.
- [ ] Measure transcript-based timing estimates against audio-labelled short
  pauses, continuous speech and true endpoints. Investigate Flux word/audio-window
  evidence on deployed interims and Scribe keepalive/commit evidence; distinguish
  capability absence, clock mapping, revision behavior and ASR/network lag.
  No missing message proves silence, and TTS alignment is not human pause timing.
- [ ] Compare overlap-allowed cues with optional provider-pause gating; expire
  stale pause opportunities and recheck source/freshness at audio admission.
  Do not lower turn thresholds, force STT commits, add endpoint waiting or silently
  enable local VAD. Optional pause hints cannot extend a candidate's lifetime.
- [ ] Review a small neutral phrase bank in the configured voice/language.
  Compare prepared playback with deadline-bounded on-demand synthesis. Include
  mandatory skips for short turns, numbers, consent, serious disclosures,
  corrections, uncertainty and explicit idle holds. Validate common listener/message
  text against bounded neutral cue content/voice/language policy; no unrestricted
  main answer disguised as a cue, unsupported-language guesses or misleading agreement.
- [ ] Freeze disjoint native-reviewed tuning/acceptance material: at least 30
  long-turn and 30 short/mandatory-skip cases per candidate language. Include
  different rates/accents, code-switching, punctuation-rich/poor and revised ASR.
  Kannada requires native phrase/audio and actual ASR review before support.
- [ ] Freeze cadence/deadline/quality gates before tuning. Starting hypotheses:
  4 seconds from first text, evaluations at most every 800 ms with changed content,
  5 seconds between cues, at most 3 per turn, opportunity life 600 ms, clips at
  most 800 ms. These are observation limits, not measured speech duration.
  Measure strict-revision rejection/starvation rather than silently relaxing it.
- [ ] Run blinded listening go/no-go. Proposed gates: at least 80% appropriate
  emitted cues and 60% coverage of annotated long-turn opportunities, without
  systematic preference for no cues; record counts/disagreement and all skips.
  Require zero controlled lifecycle/permission/duplicate violations and zero
  deterministic mandatory-skip cues. A policy that emits nothing does not pass.
  Record a scope/threshold decision with evidence if a gate is infeasible.
- [ ] Implement bounded participant cue state and isolated decision/preparation
  workers with one decision/one coalesced opportunity, node-wide capacity,
  replacement-transcript revisions and exact mode/source/output correlation.
  Empty, stale, final-only, uncertain, late or busy opportunities skip safely.
- [ ] Prepare/cache through the selected TTS voice with tenant, permitted service,
  model/voice/config, language, phrase/prosody revision and audio-format identity.
  Bound cache/preparation; voice changes invalidate clips. Use a separate scoped
  preparation operation that cannot clear live TTS. Missing assets warm in the
  background and do not block call readiness; no credentials/transcripts in keys.
- [ ] Play cues through C's listener-mode output-purpose boundary, without ending
  the human turn, invoking incoming interruption decisions, resetting idle_timeout
  timers or adding ordinary assistant history. Preserve earlier real overlap.
  Ambiguous simultaneous humans/agent listeners skip until the target is unique.
- [ ] Give main response/opening/briefing/hold/transfer and explicit idle holds priority. Drop queued
  cues and stop active cues on confirmed endpoint, permission loss or response
  admission; await bounded sink settlement before main audio. Late results never
  revive a cue or reset speaker mode; no failure restarts the main agent/tools.
- [ ] Bound cue audio bytes/duration and retain existing output credit, drain and
  backpressure. Test exhausted credit, oversized audio and missing/failed clear
  acknowledgments. On cancellation failure prevent overlapping outputs and use
  the established sink-recovery boundary without making the optional cue fail
  the call; record recovery delay instead of releasing competing audio blindly.
- [ ] Wire explicit cue opt-in through existing configuration/publication and
  prove disabled operation, inherited/explicit values, prepare/join/restart,
  source replacement and transfer. This setting is independent of classifier
  default-on; production cue default remains a listening-acceptance decision.
- [ ] Record selection/preparation usage and attempted/skipped/admitted/played/
  discarded cues with qualified evidence, separate from normal turns. Cache
  replay is not a new synthesis charge. Preserve permitted inspection/recording
  evidence; no raw transcript or high-cardinality IDs in metric labels. Define
  any authoring/inspection UI tasks at implementation promotion and inspect any UI.
- [ ] When optional TTS timing exists, use A/B's common contract to distinguish
  generated cue text from qualified played cue text on interruption, preserving
  estimated/unavailable cutoffs. Test that this evidence never creates an ordinary
  assistant exchange; timing absence must not block E. Verify the provider
  combinations with real interrupted cues in F.
- [ ] Run a real configured browser call with local VAD off: long utterance,
  audible cue, uninterrupted human transcript, confirmed endpoint and exactly
  one main answer. Verify gain, mixing/ducking, clipping, speakerphone echo and
  no transcript-match blacklist. Compare with no cues; proposed added response
  delay p95 <=50 ms after main audio is ready, reporting maxima and failures.
- [ ] Replay revised/duplicated/out-of-order/stalled/missing transcripts, slow
  selector/TTS, saturation, owner death, stale callbacks, permission revocation
  and hangup. Compare real opportunity windows and cost, then pass common gates.
  If the experiment fails, keep runtime activation and this checkpoint open.

## Checkpoint F — Telephone calls and validated language coverage

**Exit:** the combined feature works in declared telephone/browser profiles,
with measured ordinary-response latency and explicit language/resource support.
This expands deployment coverage, not merely reruns root tests.

- [ ] Freeze the supported STT/TTS/LLM/transport/language matrix and classify
  profile ownership/capabilities. Inventory remaining provider onset/final/eager/
  resume/endpoint signals and actual protocol evidence. Add supported profiles
  through the same contracts; explicitly retain unsupported/native-STS behavior.
- [ ] Verify provider-confirmed endpoint dispatch with no extra wait and the
  separately selected local fallback in compiled calls: long forced segments,
  renewed speech, missing/late final text, duplicate endpoints, old snapshots,
  source replacement, hold, transfer and teardown. Optional VAD must not add
  delay to the confirmed provider path or alter cue-mode handling.
- [ ] Expand classifier validation on fresh native human/ASR material, prioritizing
  English/Hindi and Kannada including `oudhu`, native scripts/transliteration.
  Cover French `oui`, `yes/hmm`, early/ordinary `yes`, correction after agreement,
  short `stop/repeat/enough`, unfinished thoughts, `tomorrow`, long/overflow text,
  accents and mixed-language uncertainty. Freeze error/latency gates before tuning;
  only separately accepted profiles join the enabled set.
- [ ] Expand cue language/voice banks only through E's native quality gates;
  classifier language support grants no cue support. Verify per-profile defaults,
  compatibility and complete configuration/lifecycle propagation.
- [ ] Run recorded browser and telephone calls using both integrated timing
  providers, with classifier on/off and cues on/off, plus a no-timing profile.
  Demonstrate interrupted transcript/next-response correctness, useful cues,
  caller continuity, exact purpose transitions and honest remote/local evidence,
  including generated-versus-played evidence for interrupted cues with aligned,
  estimated and unavailable timing, without normal assistant-history insertion.
- [ ] Exercise fan-out recipients, simultaneous humans, listener/agent replacement,
  protected opening, private briefing, hold, transfer, source/permission loss,
  recovery, compaction and hangup across the combined behavior. No retired output,
  transcript leak, duplicate response or repeated durable tool effect is allowed.
  Exercise the message milestone's verified protocol across these voice profiles;
  own voice-specific integration regressions rather than duplicate generic format checks.
- [ ] Test one/two/four-CPU quotas with measured worker/thread/RSS budgets, cold
  startup, fair multi-call admission, tokenization, existing media/Silero and
  bounded overload. Compare more single-thread workers with multi-thread inference;
  check shared-session feasibility before assuming it saves memory safely.
- [ ] Verify the distributed image's pinned artifacts and offline startup under
  supported runtime/CPU architectures, absent/corrupt model fallback and upgrade
  policy. Model readiness never gates unrelated calls. No model binaries/history
  enter Git; general image publishing/embedded distribution retains its own gates.
- [ ] Measure last human audio, endpoint, model dispatch/first text, first
  synthesis and actual caller-side playback with correlated clocks. Report every
  ordinary-turn sample, count, median/p95/max and all misses against **1,000 ms**;
  classify tool/interrupt/failure cases explicitly, without silently excluding
  slow ordinary replies. Unresolved target misses keep this checkpoint open.
- [ ] Report timing coverage/error, false suppression/false interruption/missed
  interruption, cue appropriateness/coverage, ASR lag, echo errors, response delay,
  queue/service/LLM/stop latency, usage and CPU/memory with p50/p95/p99/max where
  meaningful. Consume the message milestone's prefix/cache evidence and report
  additional effects of voice policy. Preserve denominators, skip/failure reasons
  and privacy controls.
- [ ] Update runtime/user/provider documentation, compatibility notes, acceptance
  evidence and checkpoint progress. Pass the common gates after the final changes;
  mark the combined index entry complete only when all A–F exits pass. No source
  review or specification approval substitutes for recorded audible acceptance.

## Specification coverage and consolidation map

These mappings locate voice delivery work in A–F and identify the extracted
generic message-format owner. Normative contracts and primary
research remain in the specs; there are no separate active implementation lists.

| Specification or former task group | Owning checkpoints |
| --- | --- |
| TTS optional capability, normalized spans, clocks, rendered text and per-listener playback | A; Rime profile in B; transport expansion in F. |
| TTS generated retention, spoken transcript, model context, unknown/zero, tools, recovery and compaction | A; cross-feature/transport proof in C/F. |
| Generic structured input/history, retained native calls/responses, pending-snapshot removal, typed results and prefix/cache verification | Dedicated [message-format milestone](structured-agent-messages.md), A–C; explicit timed idle is D. This milestone A/C/F consumes its contracts and owns voice-specific integration only. |
| Former TTS A/B/C | A / B / F, with first-profile safety/history checks already required in A. |
| Classifier ownership, overlap semantics, structured result, concurrency and bounded LLM failure | C; filter-specific application in D. |
| Classifier cleaner/tokenizer/logits, overflow, language, CPU/Ortex, serving, artifact build and readiness | D; wider language/CPU/runtime matrix in F. |
| Default-on classifier preference and deferred Models-tab control | D; deployed configuration coverage in F. |
| Former contextual A/B/C/D/E | C/F profile/endpoint work; C semantic behavior; D CPU filtering; F broader acceptance. |
| Completed Scribe endpoint work | Historical baseline retained at its original link; regression obligations in C/F. |
| Cue modes, purpose, endpoint/resume and cancellation | C shared boundary; E real cue lifecycle; F combined transport behavior. |
| Cue research/prototype, optional STT timing, selection, prepared audio, cache, cadence, quality and skips | E, with experiment tasks allowed early. |
| Cue settings, inspection/usage, optional played-text evidence, byte/credit/backpressure, failed cancellation, echo and audible acceptance | E for initial browser profile; F for phone/additional profiles. |
| Former cue A/B/C/D | E experiment and configured call; E/F lifecycle, inspection and broad acceptance. |
| Design alternatives, existing-code evidence and provider source findings | Inputs to the owning checkpoint's implementation/validation, not extra work-only milestones. |
| Common tests, root/Lean checks, docs and evidence | Exit task in every checkpoint; full feature/transport matrix in F. |

## Design review — separate from implementation

Consolidation review: preserves the complete pending scope while combining work
that must be useful together. One provider/history slice, one incremental provider,
semantic call control, classifier-enabled calls, actual listening cues and expanded
telephone/language deployment are the six completion units. Prototype/component
work stays inside those units and cannot be checked off as a usable feature alone.

The first independent Astra xhigh review compared all three technical specs and
80 former checklist entries (76 pending, four completed Scribe entries). It found
all task groups owned and no false completion, with five acceptance gaps: trusted
LLM input construction, substantive post-output continuation, cue byte/credit and
failed-cancellation handling, optional timing for interrupted cues, and explicit
retired-source invalidation versus classifier fallback. These are now explicit
tasks in C/D/E/F. Binding-control wording also requires exposing missing controls,
not merely checking them. The independent Astra xhigh re-review found no material
findings remaining. It confirmed agreement across the specs, delivery review and
index, ownership of the 80 former entries, all 72 new tasks unchecked, no pending
checklists in superseded files, and verbatim preservation of the Scribe evidence.
That review covered the original 72-task consolidation. The subsequent user
clarification adds the separate simple-message specification and five tasks in
A/C, expands existing C/F acceptance, and keeps six meaningful exits. That draft
removed model-visible turn machinery and supplied pending application
calls only on the newest message, retaining completed outcomes in history.
Independent Astra xhigh review of the amended 77-task plan found no material
findings. It confirmed simple structured content, latest-only pending snapshots,
retained completion results, internal turn machinery, the two-field response,
tool/compaction/legacy/streaming coverage and meaningful A–F ownership. All 77
implementation tasks remain unchecked; historical Scribe evidence is unchanged.

The subsequent user clarification supersedes latest-only pending snapshots:
pending calls stay internal, actual outcomes append once, and earlier committed
model messages remain unchanged. A/C/F now cover settled speech before commit,
native protocol compatibility, runtime duplicate protection and cache-prefix
verification. Independent Astra xhigh review of this append-only amendment found
no material findings. It confirmed all model-channel exclusions, terminal-result
ownership, provider activation gates, speech settlement and explicit context
boundaries. Task count remains 77, all unchecked; provider feasibility and cache
performance remain implementation acceptance gates.

The user then requested a dedicated message-format milestone and explicitly
confirmed retention of original tool-call messages and responses. Five generic
tasks move out of this checklist; overlap-specific tasks consume the shared
protocol. This voice plan now has 72 open tasks, with no loss of voice scope or
historical Scribe evidence. Independent Astra xhigh review of this extraction
found no material findings and confirmed complete ownership, retained native
exchanges, configured-agent exits and acyclic dependencies. All 72 voice tasks
remain open.

The common-response/mode amendment uses one type/text/interrupt_agent reply and
frozen input-admission agent_mode. The message milestone owns the basic mode
lifecycle; voice C consumes it for cue and overlap policy. Independent Astra
xhigh re-review found no material findings after the delivery catalog gained
explicit zero/unknown examples and acceptance. All 72 voice tasks remain open.

The later user review removes those model-visible delivery examples/events and
overlap/classifier objects. Voice A/C now keep the evidence internal and send only
supported spoken text plus minimal participant input/mode. Tool formats stay
unchanged. This is an intentional simplification, not removal of internal timing,
eligibility or stale-result checks; all 72 tasks remain open. See the
[question labnote](../20261116-1107-message-format-questions.md) for source evidence
and current design-review status. Independent Astra xhigh simplification review
found no material findings and confirmed the unchanged task/dependency ownership.

Implementation progress remains separate: this planning document claims no
runtime, provider, browser or deployment verification.

The later user clarification changes common dialogue to agent_mode/message and
uses the native idle tool for stop-and-wait, allowing its associated speaker
acknowledgment before the quiet timer. C consumes message C/D, and E validates
listener/message cue proposals through its existing timing/quality gates. The
phrase_id selector remains a comparison baseline, not a competing required
production response format. All 72 voice tasks remain open; message A now owns
storage/JS migration and message D owns the runnable timed-pause slice.

Independent Astra xhigh review of this latest amendment found no material
findings. It confirmed mode/message and idle ownership, scoped acknowledgment,
early cancellation and single timeout continuation, exact-target protection and
acyclic message D → voice C → voice E dependencies. All 72 tasks remain open.
