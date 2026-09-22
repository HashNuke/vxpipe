# Agent speech-to-speech

Status: checkpoint A is implemented; B–E have focused implementation evidence
but the integrated room path and lifecycle work remain incomplete. Checkpoint F
is partially complete (service gating tests and documentation are in place).
The milestones index entry stays unchecked until the coordinated final
acceptance pass (tagged hosted check with explicit billable authorization,
bounded synthetic load, rendered UI pass, independent review, full root
gates) passes. Checkpoint A remains committed as `a31a479f` with its contract
repairs; the subsequent B–E runtime checkpoint includes its implementation
evidence in `labnotes/20260922-0819-agent-sts-completion.md` and the direct-work
labnotes linked below. Committing that checkpoint does not complete the milestone.

Implementation review repairs are still in progress. Direct-work evidence in
`labnotes/20260922-1127-direct-sts-hardening.md` covers bounded FIFO pending
turns, explicit STS failure reporting, module responsibility splits and the
delayed-onset double-interruption fix. Those focused checks do not close the
final acceptance gates. Google handle-based reconnection is now covered by
local protocol tests (`labnotes/20260922-1142-google-sts-resumption.md`), without
historical audio replay. Fresh-session context reconstruction is only a
[feasibility proposal](../sts-context-restoration.md), not implemented recovery.
The latest direct-work checkpoint passes all root format, compile, strict Credo,
unused-lock and test checks (2,166 tests, zero failures, 42 excluded; seed 0).
This does not close the remaining implementation or acceptance work below.

Real-room follow-up (`labnotes/20260922-1209-sts-room-integration.md`) repaired
STS runtime selection, allocation policy capture, readiness reconciliation and
source-disconnect cleanup. STS is now a required readiness resource; missing
policy authority and rejected enforcer registration cannot grant an allocation,
and a second source connection is rejected. Actual microphone routing into STS
is still missing. [The input-routing decision](../sts-input-routing.md) now
records separate input/output descriptor formats and the bounded, independently
credited `Media.STSIngress` primitive. Its 12 focused checks cover identity,
format, age/sequence, bounds, policy/hold, timeout, cleanup and status redaction;
the transport/room adoption path remains unwired. Capability tests
are not substitutes for that room-level proof;
the B room-proof and B/C lifecycle exit items below remain unchecked.
The input checkpoint also repaired a root-suite STT startup race: the attached
source now supplies a validated initial policy before a provider allocation can
start. See `labnotes/20260922-1233-sts-microphone-routing.md` for the failing
run, repair, focused checks and final green umbrella evidence.

Prerequisites: [Simpler speech integrations](simpler-speech-integrations.md),
[Provider integration packages](provider-integration-packages.md), and
[Rime and Google speech providers](rime-and-google-speech-providers.md). The
existing LLM + TTS mode remains a supported peer mode, not a compatibility path.

Design sources: [speech provider contract](../speech-provider-contract.md),
[speech integration guide](../speech-integration-guide.md),
[provider integration packages](../provider-integration-packages.md),
[Google speech integration](../google-speech-integration.md), and
[speech session ownership](../speech-session-ownership.md).

## Runnable outcome and decision

An agent participant selects exactly one response path:

| Path | Agent capabilities | Agent speech transcript source |
| --- | --- | --- |
| Existing text model | `model_inference` plus optional `text_to_speech` | The text model's output; existing TTS playback rules apply. |
| Native speech with provider text | `speech_to_speech` | STS output transcription. |
| Native speech with recognition | `speech_to_speech` plus agent `output_speech_to_text` | STT over that agent's generated audio. |

Choose one published transcript source for each participant before admission.
If the human has STT, its transcript belongs to the human; otherwise require
STS input transcription for that human. STS output transcription belongs to
the agent; an explicitly selected agent-output
STT can instead fill that role in the separate recognition mode. Require the
selected source to exist, and fail missing text safely. No automatic provider
switch, runtime transcript fallback, duplicate transcript source, or
STT/TTS-shaped wrapper around a conversation model is introduced. STS input
text never appears as agent speech. Human STT recognizes the human's microphone
and is distinct from agent-output STT. When human STT runs alongside STS, its
final text is published but is not dispatched through the text-model `SendText`
response path: STS has already received the human audio.

Transcript-source selection does not choose who detects speech onset, ends the
conversational turn, or triggers the STS response. A selected human STT may
provide caller text while the STS provider still owns conversational
turn-taking. Select and test the turn-control mode separately. Only one
authorized activity signal may trigger each barge-in.

`speech_to_speech` is a Call Engine capability belonging to the **agent
participant**. Its temporary subtree lives under that room incarnation's
`RoomCapabilitySupervisor`. The provider owns its bidirectional model session,
wire protocol, turn identifiers, resumption handle, and model context. The
room owns source selection, policy and permission decisions, public turn/event
IDs, transcript projection, output sink, playback evidence, transfers, and
interruption. The provider cannot publish directly to the room or impersonate
a participant. Agent-output STT, when selected, is a separate child under the
same agent-owned tree; its input is the STS output audio, never the caller's
microphone. OTP links, monitors, and the owning supervisor end the whole tree
on participant/room loss. No application-wide STS supervisor or cross-call
queue is needed.

The first supported live route is one active human source connection per STS
session. The room does not send its mixed output back as model input or combine
multiple speakers into a single unattributed stream. An unsupported concurrent
source/transfer arrangement fails admission explicitly until a source-handoff
contract is proven. Existing text-model calls remain unchanged.

## Contract and internal API changes

Add `:sts` to `Vxpipe.Providers` and an optional `Vxpipe.Providers.Google.STSSession`
manifest entry only after that adapter works. Add
`Vxpipe.CallEngine.Speech.STSProvider` and a closed STS descriptor alongside,
not inside, `STTProvider`/`TTSProvider`. Suggested required operations:

| Operation | Project-owned meaning |
| --- | --- |
| `configure(public_options)` | Pure validation of model, voice, PCM formats, transcript coverage, turn/interruption evidence, usage identity, and readiness. No credentials or I/O. |
| `start_link(private_init)` | Bounded local startup under the agent capability tree; remote readiness is asynchronous. |
| `push_audio(pid, source_ref, pcm)` | Bounded admission of one permitted, correctly attributed input chunk. `:busy` means the chunk was not accepted. |
| `input_activity(pid, source_ref, :started \| :ended)` | Bounded, ordered boundary from the selected external or hybrid turn controller; unavailable in provider-controlled mode. |
| `push_text(pid, source_ref, text)` | Bounded explicit text input for existing typed-chat/continuation workflows; preserve the provider's interruption semantics. |
| `interrupt(pid, turn_ref, playback)` | Promptly fence stale output, notify the model as its API permits, and keep the cancellation identifier until terminal isolation. |
| `send_tool_result(pid, call_ref, result)` | Deliver a bounded, authorized result to a valid provider call association. A cancelled association cannot revive old speech; the engine retains an already-submitted invocation result for later reasoning. |
| `close(pid)` | Idempotent explicit shutdown; ordinary supervision guarantees cleanup. |

Source attribution travels on the scoped channel, which stamps every event
with source/agent identity plus a generation or turn reference, so the
implemented callbacks carry no separate `source_ref` argument: one permitted
input stream exists per STS allocation. `push_text` carries an engine-issued
text reference instead, and the provider publishes `:input_submitted` with it;
unadmitted references settle as stale. `input_activity` is rejected by the
channel in provider-controlled turn mode before provider admission.

The checkpoint-A output contract uses consumer-authorized
`Session.admit_output/2`, a fresh engine output reference, the shared single-chunk
PCM credit path, and `:output_completed` correlated to both output and provider
turn references. Only acknowledged completion plus bounded local playback
settlement releases the slot. Input admission does not authorize output. See
[STS output admission](../sts-output-admission.md) for the decision and
[the author guide](../speech-integration-guide.md#authorizing-and-settling-sts-output)
for the exact protocol. Tool-call events carry bounded JSON arguments and the
provider turn association; room authorization and execution remain checkpoint C.

The closed event vocabulary needs readiness, input speech activity, optional
input transcript, output audio, output transcript, generation/turn completion,
interruption, tool call/cancellation, usage, and safe failure. Every event is
stamped by the scoped channel, acknowledged before room handling, and tied to
source/agent identity plus a generation or turn reference. Multiple fields in
one provider message must all be processed. Keep provider IDs private. Extend
`Speech.Descriptor`, `Speech.Event`, `Speech.Session`/channel as needed, but do
not force STS through the complete-text TTS request or STT turn-end contract.
The descriptor must state supported provider, external, or hybrid turn-control
modes, how output text settles (an explicit transcript end or a documented
generation boundary), and whether the provider can reconcile its conversation
history to transport-qualified egress evidence after interruption. These are
admission facts, not guesses based on
message arrival order. A transcript delta alone cannot open/close a turn.
Provider modules can share private socket/PCM helpers without acquiring another
public transport behaviour. Add a provider author example and conformance test
to `docs/speech-integration-guide.md` and Call Engine test support.

Extend `CallSpec.Capabilities`, `ResolvedCallPlan.Capabilities`,
`CallSpecCompiler`, `CapabilityCatalog`, `PlanStartup` and agent activation
with a closed `speech_to_speech` selection and a distinct agent-only
`output_speech_to_text` selection that resolves through the existing `:stt`
provider manifest. For an agent, reject simultaneous
`model_inference`/`text_to_speech` and STS; require agent-output STT only
when the selected STS descriptor lacks output transcription. Record the
agent-output STT role explicitly so it cannot be mistaken for human STT.
Do not inherit a human STT default into the agent-output slot.
Defaults and published call-spec revisions retain their existing meaning;
validate the new combination at compile/admission, without rewriting stored
specs or accepting unknown models. Extend transfer preparation, readiness,
inspection, usage, and call-history projections for the new capability.

Create a dedicated agent STS tree and room-facing controller; do not inflate
`AgentRuntime.Coordinator` with a second model lifecycle. Reuse the existing
room source audio conversion and bounded sink where formats agree; add explicit
conversion/rejection where they do not. Input fanout to human STT and STS must
remain bounded and independent: one slow consumer cannot grow the other one's
mailbox. Source audio is admitted only after the room's media-policy snapshot
and `audio_route_permitted?` from the human to the agent are checked. Agent
audio egress separately checks its route to each listener. Revocation fences
queued bytes before
the next policy interval. A prepared replacement cannot consume audio until
adopted. Fail closed on uncertain source identity, policy revision, buffer
overflow, or allocation loss. The same admission and revocation checks apply
to provider-supplied input transcripts, agent-output transcripts, proactive
speech, and tool results. A transcript is never a substitute for an allowed
audio route or `transcript_route_permitted?` check.

RoomAuthority creates public `ParticipantTurn*` events for the human and
`AgentSpeech*`, `AgentTurn*`, and text output/transcription events for the agent.
It is the only publisher through `EventPublisher.publish_transcript` and
`TranscriptRouter`. Provider text is evidence, not permission. Model-provided
output text and sidecar STT text both use the **agent participant** as source;
input text uses the human source only when authorized. Track generated,
accepted, and locally paced egress audio separately. The current sink's pacing
acknowledgement is not proof of remote playout or hearing; the
[recording contract](streaming-recordings.md) makes the same transport-egress
distinction. Do not describe an early transcript as heard: release final spoken
text only after the matching
output passes the best available egress fence, and label that evidence
honestly. On interruption, clear queued audio first, fence late audio/text,
report the local egress duration as an estimate, and omit or explicitly mark
text that cannot be aligned to that prefix. STT over generated audio may start
before egress, but its public transcript follows the same fence. A provider's
full generated transcript is not proof of what the caller heard. On
zero-egress interruption, publish no spoken prefix; the adapter must also
settle the provider's retained history or fail the session.

The room's interruption and media-policy checks remain authoritative. Use
permitted human speech onset (existing human STT evidence or a separately
proven source activity signal) to interrupt local playback promptly; also
honor a provider `interrupted` event. If Gemini 3.8 Live cannot provide prompt onset evidence,
prove a bounded local source activity detector or require an explicitly
selected human STT before enabling the mode; a late transcript is insufficient.
Select the response-triggering turn mode independently of transcript sources:
provider detection, human-STT-driven external boundaries, or a documented
hybrid. Provider detection is a valid candidate even when human STT supplies
the published caller text. Do not disable it merely because STT exists. If
external boundaries are selected, the STS contract must deliver ordered
speech-start/end controls to the provider and prevent its automatic detection
from triggering a competing response. If hybrid is selected, define which
signal controls onset and which controls end. Reject a combination whose
provider cannot honor the selected mode. A late transcription cannot itself
trigger a response or override denied input, speaker identity, or hold.
Do not wait for input transcription, which may arrive late. Provider turn end
and sink playback end are distinct. A provider completion cannot finish the
public agent turn until playback and its selected transcript source settle.
Proactive model output must pass the same room authorization and attribution
gate as a prompted response; otherwise discard it safely. Tool calls use the
current allowlisted tool and variable permissions, scoped to the active agent
turn/activation; provider cancellation IDs remain available until the matching
tool result or cancellation is settled. A room hold, transfer, or teardown
invalidates the old generation before any new source is admitted.

## Cross-provider fit and limits

[OpenAI Realtime](https://developers.openai.com/api/docs/models/gpt-realtime-2.1)
is a conversational speech-to-speech candidate. Its
[event guide](https://developers.openai.com/api/docs/guides/realtime-conversations)
separates audio, output transcription, response completion and user activity.
For a server-side WebSocket, the client stops playback and truncates the
model's conversation item to the played audio duration after barge-in. The API
explicitly does not provide precise text/audio alignment for the truncated
transcript. This supports a transport-qualified room egress ledger and an explicit
"unverified spoken prefix" outcome. OpenAI's separate
[GPT-Live API](https://developers.openai.com/api/docs/guides/live-conversations)
streams transcript fragments without a completed-turn marker or item ID and
keeps their approximate timestamps separate from audio playout. That API
needs a separately proven turn/text settlement rule before it could conform;
it is not implied by Realtime support. Neither OpenAI API is in this
milestone's implementation scope.

ElevenLabs' [speech-to-speech endpoint](https://elevenlabs.io/docs/api-reference/speech-to-speech/stream)
is a voice changer: it converts supplied speech into another voice. It is not
a conversational agent session with model turns, tools, and agent output
transcripts. [ElevenAgents](https://elevenlabs.io/docs/eleven-agents/overview)
is a hosted STT/LLM/TTS agent stack, not that voice-changing model; its
[client events](https://elevenlabs.io/docs/eleven-agents/customization/events/client-events)
can deliver the final agent text after audio begins and later correct it on
interruption. Neither surface qualifies for this STS contract just because it
accepts and emits audio. Voice conversion or hosted-agent support requires a
separate design and room-policy fit review.

Google documents output transcription as unordered relative to audio but
states its final output transcription precedes `generationComplete` or
`interrupted`; use those boundaries for the Google adapter while retaining
the independent playback fence. Its
[Live API reference](https://ai.google.dev/api/live) says model output can be
generated faster than real-time playback, and its
[VAD guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
says interrupted history retains information already **sent to the client**.
Sent bytes may be ahead of heard bytes. Before the hosted badge is enabled,
prove that this difference cannot make a consequential subsequent reply
assume unheard speech, or document and enforce a bounded mitigation that
meets call-quality acceptance; otherwise leave Google STS gated. No precise
history-truncation operation is assumed for Google.

## Google 3.8 Live profile

The initial hosted STS selection is `provider: "google"`,
`model: "gemini-3.8-live"`, with a provider-owned voice option. Google's
[model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live)
identifies the stable model and says audio is the response modality; output
audio transcription must be enabled to obtain response text. The
[Live API reference](https://ai.google.dev/api/live) exposes
`inputAudioTranscription`, `outputAudioTranscription`, output audio,
`generationComplete`, `turnComplete`, `interrupted`, tool calls and
cancellations, `goAway`, and session-resumption updates. It does not guarantee
an exact ordering between input transcript, output transcript, and audio;
the adapter must correlate and bound pending evidence. The
[capabilities guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
specifies 16-bit little-endian PCM, native 16 kHz input and 24 kHz output.
Use one server-side WebSocket under the scoped tree and do not expose the
saved key to clients, logs, status, or tests.

The [session guide](https://ai.google.dev/gemini-api/docs/live-api/session-management)
documents an approximately ten-minute connection limit, `goAway`, resumption
handles, and context compression. Implement bounded in-session resumption as
continuity of the **same** capability, with a generation fence and no audio
replay unless acceptance can be proven. It is not a provider/model fallback.
If resumption cannot establish identity and ordering before its deadline, fail
the capability rather than silently start a fresh conversation. Gemini 3.8
Live's default non-blocking tool behavior must be mapped to the current
authorized tool lifecycle; the [tool guide](https://ai.google.dev/gemini-api/docs/live-api/tools)
and model card require explicit attention to scheduling and cancellation.
Enable context compression only with a tested history/usage boundary.

The [pricing guidance](https://ai.google.dev/gemini-api/docs/live-api/best-practices)
notes extra transcription tokens and accumulated session context. All ordinary
tests and loads must use Morse/fake sockets. Real Google interoperability is
an explicitly tagged, opt-in lane with a short fixed budget and no credentials
in fixtures; do not run it without separate authorization for billable calls.
Map `usageMetadata` to the existing provider/activation usage projection when
present; do not infer billed tokens or price from PCM byte counts. Include
the extra STT session as a separate usage source when that mode is selected.

## Example call

1. A caller's permitted mono PCM frame enters its connection. The room checks
   source identity and policy revision, then offers the frame to the agent's
   STS allocation and, if selected for the caller, the independent human STT.
2. The provider sees speech activity and begins generating 24 kHz audio. The
   agent capability forwards credited chunks to that connection's output sink.
   RoomAuthority opens one agent turn and publishes local egress progress from
   sink acknowledgements, not generated bytes or a claim of remote hearing.
3. With Google output transcription, the adapter holds the text beside its
   model generation until the room can publish it under the **agent** identity.
   For a provider without that feature, the same output audio is offered to
   the agent-owned STT and its resulting text takes that single role. The
   human STT, if selected, publishes the caller's words. Otherwise the STS
   input transcription is the caller's sole transcript source. This choice
   does not determine which detector triggers the STS response.
4. The caller speaks over the reply. The room fences old output and interrupts
   the sink and STS generation; a late transcript or tool result cannot revive
   the old turn. A submitted tool continues within its original timeout and
   its result remains available for the next turn. The public interruption
   records the locally acknowledged egress estimate, not a claim about what
   the caller heard.
5. If a tool is invoked, the room checks the agent's active permissions and
   sends a bounded result to that same model session. On leave or transfer,
   stopping the agent capability tree closes its socket and any output STT.

## Vertical checkpoints

Implement the **full milestone**, including all three response/transcript modes,
Morse, Google Live, tools, transfers, Console integration and documentation.
The checkpoints are implementation slices, not separate broad verification
cycles. For each behavior change, write the smallest focused failing test,
make it pass, and run only the relevant focused child tests needed to keep that
slice usable. Record that evidence and move on. Do not repeat the umbrella
suite, synthetic load, full rendered UI pass or independent implementation
review after every checkpoint. If a focused test proves new call/app
instability, investigate it immediately rather than deferring a known failure.
Commit only when implementation commits are requested.

After the implementation tasks in A–F are in place, run one coordinated final
acceptance pass: integrated call scenarios, rendered UI inspection, bounded
local synthetic load, implementation reviews and all root verification gates.
Fix findings and rerun affected focused checks, then rerun final gates only as
needed. Keep the Google production selection and service badge gated until
its hosted acceptance check passes; the check remains opt-in for billable use.

### A — Selection and contract, local only

- [x] Add a failing Call Engine test for the three valid agent modes, illegal
  STS + LLM/TTS combinations, per-participant transcript-source requirements,
  turn-control selection independent of those sources, and unchanged
  published specs. Add `speech_to_speech` to call-spec/resolved structs,
  compiler, catalog, startup and inspection/usage schema where needed. Add
  the explicit `output_speech_to_text` agent selection and reject accidental
  inheritance from human STT defaults.
  Evidence: `labnotes/20260922-0539-agent-sts-checkpoint-a.md`; STS selection
  (5 tests), usage projection (+1), inspection presenter (+1); old
  LLM + TTS path unchanged.
  Repairs (uncommitted): independent review
  (`labnotes/20260922-0558-review-sts-contract.md`) found a stored-plan
  inspection regression plus contract gaps. The first repair added durable
  decode normalization, ordered `push_text`/`input_activity` commands and
  descriptor/source-selection facts. Re-review
  (`labnotes/20260922-0650-verify-sts-repairs.md`) confirmed the persistence and
  activity fixes but found five remaining issues. Their red-green repair is
  recorded in `labnotes/20260922-0708-finish-sts-contract.md`: explicit output
  admission/credit/settlement, submission deduplication, directional transcript
  coverage, bounded tool arguments with turn association, and mode-consistent
  endpointing validation. Morse conversation generation and room wiring remain B.
- [x] Add a failing independent-provider conformance test, then implement
  `STSProvider`, descriptor/event/channel rules, bounded commands, identity
  fencing, activity/text-settlement/history capabilities, and provider
  manifest `:sts` support. Update provider and speech author docs with exact
  callback, event, configuration, and error contracts.
  Evidence: STS session (3 tests) + contract (5 tests) through the owned
  Channel/Session machinery; Morse STS lifecycle; `docs/speech-integration-guide.md`
  STS section. Hosted output-STT resolution and turn-event drain stay deferred
  to D/B (fail closed now); no manifest entry until E.
  Follow-up evidence: independent `STSConformanceTest` and `STSOutputTest`
  exercise output, timeout, ownership, stale-reference and failure boundaries,
  including ten concurrent allocations completing 100 credited output turns.
  This is a local contract probe, not ten integrated calls or the final
  milestone acceptance load test.
- [x] Exit: local contract/compile tests prove unsupported providers fail
  closed and old LLM + TTS selection still runs. No STS service badge yet.

### B — Morse STS with provider transcript

- [ ] Prove a real room call for one human audio turn producing Morse audio
  and an agent-attributed transcript, including policy denial, no mixed-audio
  echo, source mismatch, mid-turn policy revocation, transcript-route denial,
  hold, and teardown. With human STT selected, its text path stays the sole
  caller transcript: STS input text is suppressed and nothing dispatches
  through the text-model `SendText` path. Without human STT, STS input text
  is the sole caller transcript. Proven at the agent-owned
  `Capability.SpeechToSpeech` boundary with the real media-policy predicates
  and the real output-sink protocol so far; that is partial evidence, not a
  room-test equivalent. A compiled real room now accepts framed Morse PCM
  without human STT, decodes its reply as RECEIVED HI, and publishes the agent
  transcript only after sink playback settlement. Independent human-STT fanout,
  native transport conversion and the remaining room lifecycle cases are still
  required before final acceptance (see F).
  Evidence: `capability/speech_to_speech_test.exs` (12 tests: reply,
  attribution, denial, echo, mismatch, revocation, transcript denial,
  human-STT suppression, hold, teardown isolation, redaction, tool
  forwarding, owner loss).
- [x] `Provider.MorseCodeSTS.Session` generates real Morse conversations
  (decode caller audio, reply `RECEIVED <text>`, credited output through the
  admitted output reference) with provider/external/hybrid turn control, plus
  its private tone/text codec reuse. The public provider namespace is
  `Vxpipe.Providers.MorseCode` (`STTSession`, `TTSSession`, `STSSession`)
  with a credential-free manifest (`morse` in `Registry`); the
  `CapabilityCatalog` resolves Morse selections through that manifest.
  Agent-owned STS tree (`Capability.SpeechToSpeech.Tree`) lives under
  `RoomCapabilitySupervisor` with bounded input/output, egress-fenced
  transcript routing and `start/stop_speech_to_speech`. Credential-free local
  configurations only.
  Evidence: `morse_sts_conversation_test.exs`, `sts_turn_control_test.exs`,
  `providers/morse_code_test.exs`, `plan_startup/sts_activation_test.exs`
  (STS runtime resolution without a text model); old LLM + TTS suites green.
- [ ] Slice exit: integrated room tests prove Morse reply, attributed
  transcripts, redaction, no cross-room state and unchanged LLM + TTS
  behavior. `sts_call_test.exs` now covers the embedded PCM round trip and real
  publication path, startup/readiness/source cleanup, source allocation guards,
  framed receiver checks, hold epochs and entry-install binding for an earlier
  attachment. `ConnectionReadiness` rejects selected STS without exact ingress
  evidence. WebRTC/telephony conversion, all three transcript modes and the
  remaining lifecycle cases are still open. See `docs/sts-input-routing.md` and
  `labnotes/20260922-1309-sts-room-input.md` for the checkpoint evidence/limits.

### C — Interruption, tools, and transfer lifecycle

- [x] Morse session/capability tests for human speech onset handling,
  queued playback, zero-playback interruption (`:no_prefix`), late
  audio/text fencing (ack-and-discard, no revival), provider interruption
  echo with terminal isolation, proactive-output discard without turn
  evidence, text input, tool call/cancellation with bounded JSON arguments,
  room hold, owner death ending the owned tree, and transfer-shaped teardown
  (tree stop/start isolation). Provider, external (boundary-driven) and
  hybrid (recognition plus boundary) response triggering are proven
  independently of the caller transcript source with no duplicate responses
  (`sts_turn_control_test.exs`). A submitted tool result is accepted once;
  interrupting first cancels it (`tool_cancelled`) and the id stays stale so
  old speech cannot revive; the next turn proceeds independently.
  Prompt onset without human STT is proven through provider detection; the
  external mode path requires explicit boundaries. RoomAuthority-level
  wiring of interruption policy, allowlisted tool execution, transfer
  preparation/handoff and readiness/first-message integration remains
  final-acceptance work; the capability exposes the owner-message protocol
  (`vxpipe_sts_*`) and `interrupt/hold/release/apply_policy/stop` for it.
  Evidence: `sts_tool_test.exs` (3), capability tool/owner tests,
  `sts_turn_control_test.exs` (4), revocation/hold/teardown tests.
- [x] The STS controller honors the existing contracts: policy-gated
  admission and revocation fencing, allowlist-shaped tool evidence (room
  authorization stays the owner's duty), readiness via `vxpipe_sts_ready`,
  generation-fenced cleanup, and explicit rejection of concurrent second
  sources (`:source_mismatch`) and unsupported handoff. Cancellation IDs
  survive until the matching result or cancellation settles.
- [ ] Slice exit: real room interruption/hold/transfer tests prove one
  terminal turn outcome, zero stale queued playback, bounded command handling
  and cleanup after owner loss. Wider scenario and latency assessment stay
  deferred to final acceptance.

### D — STS plus agent-output STT

- [x] A Morse variant declaring no output transcription fails selection
  without `output_speech_to_text` and yields exactly one agent transcript
  with it (selection rules proven in checkpoint A and unchanged).
- [x] Credited STS output feeds an agent-scoped STT allocation in the same
  agent-owned tree (separate scope, caller microphone never connected), with
  `STTProvider.finish_input/1` finalization at the STS generation boundary,
  bounded fanout (busy drops counted, sink never blocked), policy
  attribution and playback fencing. The optional finite-input operation was
  needed by the Morse adapter and added as an optional callback with author
  documentation; human conversational onset/turn-end requirements are
  untouched.
  Evidence: `stt_finish_input_test.exs` (2),
  `capability/speech_to_speech_output_stt_test.exs` (5: single agent
  transcript, no caller transcript or duplicate, denied policy, STT failure
  honesty with next-turn recovery, slow-consumer isolation). The
  provider-transcript path remains independently green.
- [x] Exit: complete and interrupted turns, denied policy, STT failure, and
  slow consumer cases settle honestly. Interrupted output restarts the
  output STT so late text cannot leak into the next turn.

### E — Google Gemini 3.8 Live

- [x] Fixture-driven tests for setup, voice, PCM conversion (16 kHz in /
  24 kHz out), multi-part message parsing, out-of-order transcripts/audio,
  generation versus playback completion, interruption before first audio,
  selected turn-control mode, tool cancellation, `goAway`, resumption,
  expiry and unsafe/missing resumption handle. Sent-ahead-of-playback
  interruption and the subsequent turn are exercised with a fence-window mute;
  the adapter declares `history_reconciliation?: false` and keeps no precise
  truncation, so the hosted gate must still prove that unheard speech cannot
  change the next reply (or enforce a mitigation) before production use.
  Evidence: `providers/google/sts_test.exs` (7),
  `providers/google/sts_session_test.exs` (17) with the fake
  `TestGoogleSTSTransport` (24 passing, seed 0). Handle handoff tests also
  cover revocation, idle connection loss, setup deadlines, playback settlement,
  stale-socket fencing and no historical input or generated-speech replay.
  `docs/sts-context-restoration.md` records the boundary and hosted limitations.
- [x] `Vxpipe.Providers.Google.STSSession` and private `STSSocket` live under
  the existing Google package. Credentials resolve privately, output
  transcription is enabled, and the manifest keeps NO `:sts` entry: local
  room/contract checks pass at the fixture level, but hosted selection and
  the badge stay gated. No parallel old socket or fallback exists.
- [x] Slice exit: focused fixture/contract tests pass and the adapter remains
  unadvertised (`Registry.fetch_capability("google", :sts)` fails closed and
  the Console catalog test locks the badge off). The tagged hosted check is
  deferred to the coordinated final pass with explicit billable
  authorization; without it, Google production selection stays gated.

### F — Service UI, documentation, and final acceptance

- [x] Backend service-binding capability response flows from
  `Registry.catalog()`: Google exposes no `s2s`, and credential-free Morse
  never enters the credential-backed setup catalog (Morse remains a local
  test option). The Console setup catalog offers no `s2s` provider or model
  choice; the badge stays disabled until final hosted acceptance.
  Evidence: `admin_services_endpoint_test.exs` catalog assertion with
  s2s-gate refutes; `setupCatalog.test.ts` s2s-gate test (3 tests green).
  No second Google credential entry was created.
- [x] Updated `docs/provider-integration-packages.md` (Morse manifest row,
  Google STS gated note), `docs/speech-provider-contract.md` (Morse
  namespace, optional `finish_input`), `docs/speech-integration-guide.md`
  (Morse reply generation, agent-output STT, Google adapter, conformance
  commands), and this milestone/index checklist state. Transcript provenance
  (caller vs agent, provider vs sidecar STT) and the lack of automatic
  fallback are documented in the guide and milestone decision section.
- [ ] In the coordinated final pass, run the tagged Google hosted check only
  after explicit authorization for billable use and within a short fixed
  budget. Check an interrupted reply followed by another turn and resumed
  session followed by another input, alongside the ordinary short turn. Enable
  production selection and its service badge only after that gate passes;
  without authorization, record the gate as pending and leave the milestone
  incomplete.
- [ ] Run a bounded local synthetic load (at most about half the machine's
  resources) comparing current LLM + TTS calls with Morse STS and STS + STT.
  Measure admission/startup, input acceptance, speech onset, first audio,
  playback acknowledgement, turn completion, interruption and failure
  isolation p50/p95/p99 plus drops, mailbox growth and cleanup. Pause and
  investigate any proven new call/app instability before shipping.
- [ ] Run focused child suites and root format, warnings-as-errors compile,
  strict Credo, full tests and unused-lock gates. Verify no real-key fixtures,
  no credential/database migration loss, provider tag accuracy, and a clean
  diff. Run an independent implementation review in this same final pass.
  RoomAuthority-level publication (EventPublisher/TranscriptRouter),
  transfer/hold/teardown plumbing for STS calls, STS usage/history
  projections, and call-spec/API example updates remain open alongside the
  hosted/load/UI/review gates. Mark the index complete only after all
  applicable acceptance gates.

## Suggested code-change mapping (non-normative, 2026-09-22 review)

Suggestions only; normative behavior stays in the checkpoints above. Paths
relative to repo root unless prefixed with `apps/`.

### A — Selection and contract

- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_spec/capabilities.ex`: add
  `:speech_to_speech` and agent-only `:output_speech_to_text` to `@kinds`, struct,
  `new/2`; reject STS + `model_inference`/`text_to_speech` combos and inherited
  agent-output STT from human defaults.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/resolved_call_plan/capabilities.ex`:
  mirror the two new selections in the pinned resolved struct.
- `.../call_spec/capability_selection.ex`, `capability_requirements.ex`,
  `call_spec_compiler.ex`: validate new kinds/options, keep stored specs unchanged,
  carry selections into the resolved plan.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability_catalog.ex`: add
  `validate/1`, `adapter/1`, `speech_options/1`, `speech_adapters/1`,
  `validate_provider_settings` branches for the new kinds (Morse + Google
  `gemini-3.8-live` settings); fail closed on unknown provider/model.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup.ex`,
  `plan_startup/agent_activation.ex`, `plan_startup/agent_model.ex`: resolve STS
  activation instead of ReqLLM when selected; keep credential lease/private-init
  boundary; cover transfer-destination descriptors.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/descriptor.ex`: add
  `kind: :sts` plus admission facts (turn-control modes, transcript coverage,
  text-settlement rule, interruption/history-reconciliation flags, 16 kHz in /
  24 kHz out formats); keep `:stt`/`:tts` validation intact.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/`: add `sts_provider.ex`
  (`configure/start_link/push_audio/input_activity/push_text/interrupt/send_tool_result/close`);
  extend `event.ex` (readiness, input activity, input/output transcripts, output
  audio, generation/turn completion, interruption, tool call/cancel, usage,
  failure), `channel.ex`/`session.ex`/`session_tree.ex`/`capability_tree.ex`/
  `scope.ex`/`allocation.ex`/`input.ex`/`playback.ex`/`audio.ex` for bounded
  commands, ordered boundaries, identity/generation fencing, no direct room publish.
- `apps/vxpipe_providers/lib/vxpipe/providers.ex`, `registry.ex`,
  `providers/google.ex`: add `:sts` capability type; declare Google STS in the
  manifest only when the adapter passes local checks.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/usage/` (`speech_to_text_projection.ex`
  pattern), `live_inspection/snapshot.ex`,
  `apps/vxpipe_calls/lib/vxpipe/calls/call_history.ex` + `usage_projections.ex`:
  extend inspection/usage/history schemas for the new capability.
- `docs/speech-integration-guide.md`, `docs/speech-provider-contract.md`: STS
  author example plus shared conformance test.

### B — Morse STS with provider transcript

- NEW `apps/vxpipe_call_engine/lib/vxpipe/call_engine/provider/morse_code_sts/session.ex`
  (+ private tone/text codec): mirror `morse_code_stt/session.ex` and
  `morse_code_tts/session.ex`; credential-free local only.
- NEW `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability/speech_to_speech.ex`
  (+ tree/state/policy/usage): agent-owned subtree under
  `room_capability_supervisor.ex`; bounded input/output, no mixed-audio echo,
  no cross-room state.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority.ex`,
  `room_authority/event_publisher.ex`, `transcript_router.ex`: publish public
  `ParticipantTurn*` (human) and `AgentSpeech*`/`AgentTurn*` (agent) events only
  via `publish_transcript`; egress-fenced agent transcripts; human-STT text never
  dispatches through text-model `SendText`.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/media/ingress.ex`,
  `media/normalized_frame.ex`, `media/output_sink.ex`, `media/pcm.ex`: reuse room
  conversion/sink where formats agree, explicit convert/reject otherwise; admit
  source audio only after media-policy snapshot + `audio_route_permitted?`, plus
  `transcript_route_permitted?` for transcripts; bounded independent fanout to
  human STT and STS.

### C — Interruption, tools, transfer lifecycle

- `room_authority.ex` interruption path + `media/output_sink.ex`: fence queued
  audio first, keep cancellation ID until terminal isolation, report local egress
  estimate, zero-egress publishes no spoken prefix.
- `room_authority/participant_transfer.ex`,
  `participant_transfer/destination_preparer.ex`, `preparation.ex`,
  `private_speech.ex`, `history.ex`, `connection_speech_preparation.ex`,
  `room_supervisor.ex`: connect STS controller to hold/transfer/teardown,
  first-message/opening, private briefing, readiness, cleanup; reject unsupported
  concurrent source/transfer explicitly.
- `agent_runtime/coordinator.ex`, `readiness.ex`, `history.ex`,
  `model_usage.ex`/`usage_rounds.ex`: scope allowlisted tools/variables to the
  active agent turn/activation; retain provider cancellation IDs until the
  matching result/cancel settles; interrupted tool result reusable next turn
  without reviving old speech.

### D — STS plus agent-output STT

- Reuse `speech/capability_tree.ex` + `session.ex` allocation: second agent-owned
  STT child fed by credited STS output only (never caller mic), with explicit
  finite-input finalization at the STS generation boundary, bounded fanout,
  playback fencing, agent-attributed text.
- `speech/stt_provider.ex` + `descriptor.ex` (conditional): add bounded
  finite-input operation/descriptor only if the selected adapter needs it; keep
  human conversational onset/turn-end requirements intact.
- `docs/speech-integration-guide.md`: agent-output STT author notes.

### E — Google Gemini 3.8 Live

- NEW `apps/vxpipe_call_engine/lib/vxpipe/providers/google/sts_session.ex`
  (public `STSSession`) + private `sts_socket.ex`: setup/voice/PCM handling
  (16 kHz in, 24 kHz out), multi-part parsing, out-of-order transcript/audio
  correlation, `generationComplete`/`turnComplete` vs playback completion,
  pre-first-audio interruption, turn-control mode enforcement, tool
  cancellation, `goAway`/resumption/expiry with generation fence, no replay;
  private credential resolution; map `usageMetadata` to existing usage
  projection (no PCM-byte billing inference).
- `capability_catalog.ex` + `providers/google.ex` manifest: advertise `:sts`
  only after fixture/contract gates pass; no parallel old socket or fallback.
- `media/pcm.ex`, `media/normalized_frame.ex`, telephony normalizer: mono PCM16
  conversion for STS input; fail closed on unsupported formats.

### F — Service UI, docs, final acceptance

- `apps/vxpipe_console/lib/vxpipe/console/admin_services_controller.ex`,
  `router.ex`, `apps/vxpipe_calls/lib/vxpipe/calls/operator_service_bindings.ex`:
  expose gated `s2s` via `Registry.catalog()` in `provider_capabilities`; no
  second Google credential entry.
- `apps/vxpipe_console/assets/src/admin/setupCatalog.json` (+ `.ts`),
  `SetupServiceCard.tsx`, `ServiceSetupModal.tsx`, `TenantSetupPage.tsx`,
  `ServiceInventory.tsx`, `sampleRecipes.ts`, `demo_samples.ex`: gated Google
  `s2s` tag/model choice; Morse stays local-test-only; frontend tests now,
  rendered desktop/mobile pass deferred to final acceptance.
- `apps/vxpipe_calls/lib/vxpipe/calls/usage_observation_projection.ex`
  (`capability/1`), `usage_report.ex`/`usage_aggregation.ex`,
  `apps/vxpipe_console/lib/vxpipe/console/call_inspection_presenter.ex`
  (`capability_name/1`) + frontend `callInspection.ts`/`CallDetailsPage.tsx`/
  `packages/react`: add S2S labels and transcript-provenance display.
- Docs: update `docs/provider-integration-packages.md`,
  `docs/speech-provider-contract.md`, `docs/speech-integration-guide.md`,
  call-spec/API examples, operator guidance; reconcile index checklist with
  evidence.

## Alternatives and implications

An STS session is not two independent STT/TTS sessions: it owns conversational
context, input audio, output audio, tools and interruption on one lifetime.
Composing the existing `STTProvider` and `TTSProvider` behaviours for it would
give two conflicting turn authorities and make transcript attribution fragile.
A second global supervisor or shared retry queue would couple calls and repeat
the previously measured startup-isolation problem. A provider publishing room
events directly would bypass the current policy and participant checks.
Automatic STT fallback after missing provider text would create two transcript
sources mid-turn and ambiguous billing; selection must be explicit. A restart
of a lost Live connection without a valid resumption handle would silently
erase model context, so it is an error. This design adds one focused capability
and keeps Elixir supervision as the recovery boundary.

## Specification review and planning evidence

Reviewed on 2026-09-21 against the current room, speech, provider and Console
code plus the linked Google documentation. The review found four constraints
that changed the initial sketch: Call Spec currently requires a text model for
agents; human STT cannot serve as agent-output STT; provider transcripts are
not ordered with audio; and Google Live connections have a shorter lifetime
than many calls. The contract and checkpoint order address these before the
Google adapter or service badge. This is a local design/dependency review,
not implementation evidence, a paid-provider probe, or an approval of hosted
interoperability.

The follow-up provider comparison reviewed OpenAI Realtime/GPT-Live and
ElevenLabs' voice changer/hosted agent APIs. Source inspections of two agent
frameworks reinforced separate turn detection, generated audio and played
audio accounting; one exposes a zero-playback truncation edge. The resulting
contract and checkpoint additions above make barge-in, turn source, call
policy, text settlement and model-history consistency explicit gates. This
is documentation review only; no hosted or load test was performed.

The subsequent turn-control review corrected an unsupported assumption that
human STT must drive the STS model whenever it supplies the caller transcript.
Google documents automatic, manual and hybrid activity detection; OpenAI
documents server and semantic VAD. The revised contract selects published
transcript sources independently from response-triggering turn control and
requires tests of the selected mode. No detector-quality comparison has yet
been measured for this app.

The 2026-09-22 scope/verification review kept the full A–F implementation and
changed only the cadence of verification. Focused red-green checks stay with
each behavior change; integrated calls, rendered UI, bounded load, independent
implementation review and umbrella gates run together after the complete
workflow is implemented. This avoids repeatedly rechecking partial slices
while still stopping immediately for a proven new instability. Google remains
unadvertised until its separately authorized hosted gate passes.
