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
The earlier runtime checkpoint passed all root format, compile, strict Credo,
unused-lock and test checks (2,166 tests, zero failures, 42 excluded; seed 0).
This does not close the remaining implementation or acceptance work below.

Real-room follow-up (`labnotes/20260922-1209-sts-room-integration.md`) repaired
STS runtime selection, allocation policy capture, readiness reconciliation and
source-disconnect cleanup. STS is now a required readiness resource; missing
policy authority and rejected enforcer registration cannot grant an allocation,
and a second source connection is rejected. The committed embedded PCM room path
now routes microphone input into STS. Native WebRTC/telephony conversion,
callback delivery and phone-room readiness now have focused evidence (43 tests,
seed 0); full native multi-mode calls and lifecycle acceptance remain incomplete.
Native checkpoint `a6615d91` and formatting-only repair `447b3045` pass all
five root gates: 2,185 tests, zero failures, 42 excluded (seed 0).
The room-transcript follow-up now covers all four caller/agent transcript-source
combinations with real embedded PCM and playback-fenced publication. It repaired
agent-output-STT admission through the shared STT provider settings; 93 focused
tests pass. Its root run completed with two Gateway handoff failures (2,191 tests,
42 excluded, seed 0); investigation is tracked below. The next identity checkpoint
gives agent output room-owned public IDs and exact-source attribution, with 101
focused checks passing. All five root gates for identity checkpoint `6f5bb3f8`
pass (2,199 tests, zero failures, 42 excluded, seed 0). The earlier intermittent
Gateway failures remain tracked rather than being declared fixed by a retry.
The next caller-publication checkpoint gives provider-controlled embedded calls
one correlated caller start/text/end pair with room-owned IDs, bounded pending
associations and source/policy/epoch checks. All four transcript modes preserve
one caller pair, including selected human STT; 146 focused tests pass (seed 0).
All five post-commit root gates for `c171a7c8` pass (2,221 tests, zero failures,
42 excluded, seed 0). The next tool checkpoint adds room-owned public invocation
and tool-only-turn IDs, exact-source/epoch settlement and a 16-pending-room-call
limit. Ordered tool retirement and supervised execution are still open; a map
limit does not bound running workers. Agent-output retirement,
complete external/hybrid room control and broader lifecycle/final acceptance
remain open. Google output-buffer/tail checkpoint `3b1fa264` has 43
focused passing checks and all five post-commit root gates pass (2,205 tests,
zero failures, 42 excluded, seed 0). This does not resolve the intermittent
handoff findings or complete the remaining milestone gates.
[The input-routing decision](../sts-input-routing.md) now
records separate input/output descriptor formats and the bounded, independently
credited `Media.STSIngress` primitive. Its 12 focused checks cover identity,
format, age/sequence, bounds, policy/hold, timeout, cleanup and status redaction;
native transport adoption is covered by the follow-up task breakdown below. Capability tests
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

Discovery-first workflow (user clarification, 2026-09-22): before implementing
any newly identified fix or addition, record it in this milestone and break it
into concrete tasks with verification expectations. Review ownership, contracts
and dependency order before starting its red test. Keep findings and unfinished
tasks visible; do not silently expand implementation scope. For authorized
checkpoints, run focused verification, commit the coherent implementation/tests/
documentation, and only then run broader umbrella gates. Gate repairs belong in
separate commits, never an amendment of the checkpoint under test.

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
  transcript only after sink playback settlement. Independent STT/STS backpressure
  and native conversion now have focused tests. All four caller/agent transcript
  combinations pass embedded PCM room round trips below; full multi-mode native calls
  and the remaining room lifecycle cases are still
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
  evidence. Native conversion is now covered below; integrated calls in all
  three transcript modes now have embedded PCM proof below; native conversations,
  public turn projection and the remaining lifecycle cases are still open.
  See `docs/sts-input-routing.md` and
  `labnotes/20260922-1309-sts-room-input.md` for the checkpoint evidence/limits.

#### Native microphone follow-up tasks (2026-09-22)

These tasks refine B's existing native-input and independent-fanout requirements;
they do not close B's room/transcript acceptance or C's transfer requirement.
At the time this list was added, the converter helper and four focused tests
were already implemented locally; transport callback tests were red. Further
implementation paused to record this breakdown per the discovery-first rule.

- [x] Add an STS-only conversion adapter using the exact connection's selected
  input descriptor and ingress, independent of human STT. Prepare and reuse
  dedicated WebRTC Opus and telephony Opus/PCMU conversion state. Prove mono
  PCM format, byte count, timestamp conversion and explicit unsupported/missing
  allocation failures. Included in the 43-test focused native regression group.
- [x] Extend WebRTC's 16-bit RTP sequence at the STS boundary so wraparound
  does not permanently reject input. Reject duplicates/reordered packets before
  touching decoder history. The same focused group proves 65535 → 0 continuity
  and rejection of the late pre-wrap packet; not a whole-call longevity test.
- [x] Prepare and retain STS conversion in the owning WebRTC connection and
  telephony media session. Deliver microphone frames to STS when human STT is
  absent; preserve updated sequence state across callbacks. Prove both actual
  transport callback paths with their existing source checks.
- [x] Extend native connection readiness to demand a microphone track for STS,
  prepare its converter in the owner process, collect the exact STS ingress
  resource, and check its policy revision. Prove a supervised native room call
  reaches ready without human STT and selected-but-unavailable STS fails closed.
- [x] Keep human-STT, STS and room-input delivery independent under bounded
  admission/backpressure. Prove one consumer's full queue cannot suppress the
  other; treat STS policy denial as a dropped frame rather than transport loss,
  with a subsequent permitted frame accepted after a new policy revision.
- [x] Reject STS transfer-candidate preparation explicitly until C's source
  handoff contract is implemented and proven. Add a focused rejection test;
  do not claim transfer support from ordinary initial readiness.
- [x] Keep the WebRTC connection within the existing module-size/SRP boundary:
  adding its STS callback takes it beyond 800 lines. After the callback tests
  are green, move its input preparation/delivery helpers into the existing
  incoming-audio module; rerun connection and malformed-packet regressions.
  Refactored after green callbacks; connection is now 769 lines.
- [x] Record focused red/green evidence and review the diff; commit this native
  checkpoint before running root gates. Record any gate repair as a separate
  task here before implementing and committing it.
  Committed as `a6615d91`; repair `447b3045` follows the task below. All root
  gates pass after both commits (2,185 tests, zero failures, 42 excluded; seed 0).
- [x] Gate repair after `a6615d91`: normalize the multiline provider keyword
  argument in `telephony/media_session_test.exs`; root format checking found
  the expression still unformatted. Verify that exact file and its focused
  tests, then commit the formatting-only repair before restarting root gates.
  Exact-file format check and all three phone-session tests pass (seed 0).

Design/dependency review: retain the Call Engine's connection-bound handle,
credited ingress and policy owner; Gateway owns transport conversion only.
Prepare converters before readiness can release input. RTP extension is private
to WebRTC STS, not a change to telephony sequence semantics. Initial native
readiness precedes broader transcript-mode and transfer acceptance; no provider,
hosted authorization or Google advertisement changes are required. This is a
local design review, separate from implementation/acceptance evidence.
Evidence: `labnotes/20260922-1344-sts-native-input.md`.
Focused verification: 43 Gateway tests pass, seed 0. Native socket/codec tests
are local; this is not carrier interoperability, rendered WebRTC acceptance,
or the final ten-call load. Umbrella gates for this checkpoint pass; B/C/F's
remaining acceptance tasks and the milestone index remain unchecked.

#### Room transcript follow-up tasks (2026-09-22)

Inspection after the native checkpoint found that provider-driven speech-start
notifications are intentionally no-ops in the room (to avoid a second
interruption), but no separate caller turn publication replaces them. STS
transcripts also use provider turn references as public correlation IDs.
These are remaining B/C publication contracts, not proof of completion from
the existing audio round trip. Record discoveries here before implementing.

- [x] Exercise compiled room calls for provider input/output transcripts,
  human STT plus provider output transcript, STS plus agent-output STT, and
  human STT plus agent-output STT. Feed real Morse PCM through the independent
  input handles, decode the agent reply, and require exactly one caller final
  transcript and one agent final transcript after playback settlement.
  Evidence: four real-room tests in `sts_transcript_modes_test.exs`, real Morse
  HI → RECEIVED HI audio, exact caller/agent source and no duplicate final text.
- [x] Repair real-call admission for agent-output STT: startup validation reads
  a nonexistent `:output_speech_to_text` provider-settings section while runtime
  resolution correctly uses `:speech_to_text`. Reuse the configured STT provider
  registry without changing the agent-only role or error path. First prove
  `PlanStartup.validate/2` fails with the valid output-STT selection, then require
  validation and both output-STT room round trips to pass. Initial room matrix:
  five tests, two failures at call admission; the other combinations and delayed
  human-recognition ordering test pass.
  The focused validator reproduces the failure, then passes with the repair;
  missing/disabled STT providers remain rejected at the output-STT role path.
- [x] Prove selected human STT cannot dispatch a second text-model response or
  interrupt a newer STS reply when its recognition onset is handled late.
  Keep response-triggering turn control independent of transcript selection;
  add a controlled event-order regression before changing that boundary.
  Existing behavior passes: suspend the room while STT/STS process real input
  and STS delivers the reply to its sink, then resume and settle playback.
  No recognition/interruption behavior change was necessary. Other turn-control
  modes and duplicate public turn handling remain covered by the open task below.
- [ ] Publish one caller `ParticipantTurnStarted`/`ParticipantTurnCompleted`
  pair from the authorized STS turn-control evidence, separately from barge-in.
  Reject stale capability/connection/policy/hold evidence; do not synthesize
  conversational boundaries merely from a transcript delta. Cover human-STT
  coexistence without duplicate public turns or a second interruption.
  - [x] Require one correlated caller start/text/end sequence in all four
    embedded transcript-source modes; first reproduce the missing STS-sourced
    pair. Preserve the existing human-STT pair without dispatching a second reply.
  - [x] Forward acknowledged caller evidence with channel sequence, exact source,
    source transcript interval and room-owned input epoch. Keep publication
    separate from immediate capability interruption. Fence held/replaced epochs
    and stale source/policy evidence at the room boundary.
  - [x] Add a bounded caller association owner: room-generated public IDs,
    duplicate suppression, no turns synthesized from text, late final text after
    turn end, and sequence retirement. Bound unsettled associations and fail the
    allocation on overflow rather than dropping text or growing history forever.
  - [x] Verify reference and binary provider IDs, wrong capability/source,
    replacement, hold/release, policy revoke/regrant and human-STT coexistence.
    Record remaining provider-level late-evidence isolation separately from
    room-message retirement; do not claim full hold/transfer acceptance here.
  - [x] Treat transcript-route denial as no permission to publish terminal
    fallback text, while still completing the permitted audio turn and releasing
    its association. Prove repeated denied-text turns do not exhaust the pending
    budget; preserve explicit caller-overflow failure attribution and cleanup.
  - [x] Keep repeated room input-open/release idempotent while already open;
    rotate the caller publication epoch only after an actual hold. Otherwise a
    readiness reconciliation could invalidate an ongoing caller association.
  - [x] Replace the room hold/release test's generic Agent stub with a real
    supervised STS capability and assert both sides' held/epoch state. The stub
    does not implement those calls; catching its exit is not lifecycle evidence.
  - [ ] Complete the same publication guarantees with external/hybrid room
    control and provider-level late evidence first arriving after hold/release
    or source-policy revoke/regrant. The owner-message epoch fence alone does
    not prove that old upstream speech cannot be relabeled into a new interval.

  Evidence: the embedded matrix first failed both STS-caller modes (five tests,
  two failures). Caller identity, sequence/epoch, denial, late-text, bounded-state,
  explicit overflow cleanup and idempotent-release checks now pass; the broader
  146-test STS group passes with seed 0. See
  [caller publication decision](../sts-caller-publication.md) and
  `labnotes/20260922-1514-sts-caller-publication.md`. This is provider-controlled
  embedded proof, not complete native/hold/transfer acceptance.
- [ ] Keep provider references private: assign room-owned public command/turn
  IDs and correlate caller transcript/turn and agent playback/terminal events
  using exact allocation/source identity. Cover duplicates, delayed evidence,
  terminal cleanup and cross-source rejection; bound pending associations.
  - [x] First harden agent-output publication: mint room-owned command/turn IDs
    at output start, preserve them through transcript and terminal events, and
    make repeated starts for an active output idempotent. Resolve the exact
    connection/owner pinned in the allocation; reject wrong agents, missing or
    replaced source connections, and late transcript/terminal evidence. Prove
    this at the room publication boundary and in the embedded room round trip.
    Ignore repeated final text for an active output and clear its associations
    when the capability is replaced; a missing source must not crash settlement.
    Evidence: eight publication-boundary tests failed before the repair; all
    eight and the five real-room transcript tests now pass. The broader focused
    startup/selection/room/capability group passes 101 tests (seed 0).
  - [x] Add caller-turn/transcript identity associations and bounded, generation-
    qualified retirement so delayed starts cannot recreate completed public
    turns. Preserve privacy for both reference and binary provider identifiers.
    Caller owner envelopes are qualified by the current capability, input epoch
    and channel sequence; adapters still own upstream deduplication before
    assigning fresh channel sequences.
  - [ ] Apply bounded retirement to agent output as well: the current active-ID
    association rejects repeated active starts, but a delayed start after its
    terminal association was removed can still create another public turn.
  - [ ] Apply the same public identity boundary to tools: inspection also found
    `inspect(call_ref)` in public tool-call IDs and provider-turn fallback IDs
    when no audio turn exists. Give tool-only turns and tool calls room-owned
    IDs, retain matching completion/cancellation associations, and test stale,
    duplicate, wrong-agent and wrong-source evidence with bounded pending work.
    - [x] Mint private-to-public tool associations before publication, including
      tool-only turns; use the same room-owned IDs in execution context, results,
      failures and cancellation. Unknown cancellation is not a new public turn.
      Keep raw private key types distinct: a binary spelling of a reference
      cannot acquire that reference's public audio/tool association. Concurrent
      tools in one private turn share the same room-owned turn IDs.
      Tool evidence cannot acquire a replaced source's audio-turn IDs or begin
      work with a held/closed input epoch. Replace the older crashing Agent
      result-receiver fixtures with an acknowledged receiver so successful
      publication tests also verify actual provider-result delivery.
      Exercise a live Morse STS room tool call through public start/completion
      events and require the action context to use those same public IDs.
    - [x] Preserve acknowledged channel order in the owner envelope and retire
      settled envelopes with a scalar watermark. Reject active duplicate calls,
      wrong agents, replaced sources and retired input epochs; clear associations
      on capability replacement. Bound both capability and room pending maps.
      Public-boundary checks now cover active duplicates, wrong agents, exact
      source/epoch retirement, unknown cancellation, replacement cleanup and the
      16-pending-room-call limit. Capability bounds and ordered post-terminal
      owner-envelope retirement now have focused regression coverage.
      Carry the acknowledged typed event, source identity,
      input epoch and source audio-policy interval to the room; remove the old
      unqualified call/cancel owner messages. Check current permission again at
      admission/result delivery, and let only a matching cancellation retire an
      old association without publishing under a replacement source. Prove
      delayed/repeated owner messages cannot reopen settled work, active duplicate
      calls preserve their first association, overflow ends the owned allocation,
      and unknown/stale results never reach a permissive provider callback.
      Hold retires provider associations without claiming to cancel submitted
      engine workers. Provider events first observed after a new epoch still
      require the separate upstream late-evidence isolation gate.
    - [ ] Replace unowned `Task.start` execution with the existing supervised
      invocation machinery under the agent-owned STS lifecycle. Distinguish
      provider association cancellation from submitted invocation lifetime:
      ordinary speech interruption fences unsent work and old provider speech,
      while already-submitted work finishes within its existing deadline and
      retains its result for subsequent reasoning. Timeout, transfer/activation
      loss and room shutdown retire local workers/timers; local termination is
      not remote rollback. Retain the existing five-second execution budget
      unless measured evidence requires a different contract. Test worker
      survival across ordinary interruption and `DOWN` on actual owner loss.
    - [ ] Complete runtime schema/permission checks and supported host, variable,
      platform and MCP binding adoption. Unsupported bindings must fail explicitly,
      not wait indefinitely for a result no executor will produce. Preserve
      submitted invocation results for later reasoning without reviving cancelled
      provider speech. Reuse bounded invocation records/completion leases,
      correlated running acknowledgements, separate private completion updates
      and blocking/non-blocking conversation admission from the approved
      [tool execution model](../tool-execution-model.md). Verify STS provider
      encodings independently; do not send a second ordinary result to a retired
      provider call or publish a fake caller turn. Submitted timeout without a
      definitive outcome is unknown, not confirmed failure. The public-ID
      checkpoint alone does not prove this gate.

    Evidence: the first identity suite failed all 16 cases; three follow-up
    source/hold tests also failed before repair. Public start/completion/failure/
    cancellation and execution-context identity now pass, including a live Morse
    STS room tool-only call. Reproduction commands and remaining limitations are
    in `labnotes/20260922-1545-sts-tool-boundary.md`.
- [ ] Record focused evidence, remaining native/lifecycle limitations and
  design decisions, then commit before broader umbrella gates. Add any newly
  exposed repair as a task before implementation; retain separate repair commits.
- [ ] Investigate root-gate failures after `f213bfb5` before final acceptance:
  `HumanTransferWebRTCTest` failed its five-participant wait-cursor/handoff case
  and its `silent_all` release-loss case (492 Gateway tests, two failures).
  Reproduce the exact cases, identify whether the release-loss injection raced
  successful completion, and prove any synchronization/lifecycle repair with
  controlled evidence. Do not widen deadlines without a measured contract reason.
  Keep any repair in a separate checkpoint; rerun all five root gates afterward.
  Isolated rerun of the exact two cases passes (two tests, seed 0, 158.9 s),
  which does not explain or repair the failures. Follow-up tasks:
  - [x] For STT release-loss injection, establish that RoomAuthority has received
    the actual capability-unavailable evidence before releasing the native gate.
    Current code waits for the mock transport's `DOWN`, which is a different
    process/boundary. Reproduce the delayed-owner ordering and test an explicit
    acknowledgement; retain bounded waits and the runtime handoff deadline.
  - [ ] Isolate missing cue/conversation audio in the five-participant scenario.
    Identify which peer and output generation loses the expected sequence;
    compare output acceptance/egress with native receipt before changing any
    fixture or production logic. A passing isolated retry is not a root cause.
    Root run after tool identity checkpoint `3c3456c6` reproduces the same test
    at an earlier stage: the returned listener receives no expected 250 Hz wait
    audio within the existing two-second bound after reconnection (test line
    587). All 2,243 tests ran with one failure, 42 excluded, seed 0; Call Engine
    passes 1,084 tests and the other four root gates pass. The isolated Gateway
    agent owns investigation of both observed failure stages.
    - [x] Capture per-connection native output generation, accepted PCM and RTP
      egress/receipt for the original final-audio failure and the subsequent
      returned-listener wait-tone failure; use bounded native reproductions.
    - [x] Exercise delayed STT capability delivery while the native gate is
      paused, then acknowledge actual RoomAuthority receipt before gate release.
      Preserve existing runtime deadlines and verify destination/participant loss.
    - [x] Add a deterministic regression for any identified listener/output
      ordering defect before repair, and record focused red/green evidence.
      Hold the audience phase across a participant's departure and rejoin before
      private media exists: participant-ID-only reconciliation calls the dead
      player (`:noproc`) and produces recovery audio instead of waiting audio.
      Replace only departed playback ownership; preserve surviving sink cursors.
    - [x] Reproduce attachment during adoption without a policy membership
      change. Instrumented final-audio failure found a connected output still
      held at provisional generation 1, with no accepted/submitted audio or RTP
      egress. Check that adopted-release validation compares the captured
      inventory with the prepared/cued connection set before releasing media.
    - [ ] Resolve private policy refresh when departure/rejoin skips revisions
      between worker observations. Controlled native reproduction returns
      `:private_media_changed` before wait-player reconciliation: private revision
      8 to room revision 10 rejects `:unexpected_policy_revision`. Private refresh
      applies the speech capability first. Shared STT/policy changes require parent
      coordination, not a timeout increase or invented intermediate policies.
  Gateway checkpoint evidence: nine bounded native cases pass (seed 0), covering
  coalesced departure/rejoin, attachment during adoption, and destination/participant
  preparation/adoption/release loss. Controlled reds distinguish dead wait-player
  ownership, omitted provisional output, and transport DOWN versus room receipt.
  Details and the still-open private-policy reproduction are in
  `labnotes/20260922-1610-gateway-handoff-ordering.md`. The outer investigation and
  final serial root acceptance remain open; passing retries do not close the
  separately reproduced private-policy revision gap.
- [x] Align the STS capability test fixture's asynchronous readiness wait with
  its explicit provider-start deadline. A focused run alongside native WebRTC
  reproduction failed its implicit 100 ms `assert_receive` despite the fixture
  granting startup 5,000 ms. Verify the actual startup contract, use a bounded
  matching readiness assertion, and rerun the relevant suite. Do not change any
  runtime timeout or audio/turn latency assertion for this fixture repair.
  The assertion and `PrivateInit.open/2` now share the same 5,000 ms fixture
  deadline; the complete 101-test focused group passes during native reproduction.

Local design/dependency review: transcript-source choice remains pinned at
compile/admission. The room owns public identities and routing; the capability
owns provider evidence and immediate playback fencing. Do not reintroduce
`SendText` responses for recognized microphone text. Integrated transcript
proof precedes public turn/identity repairs and the final concurrent-call load.
This review is separate from implementation evidence. Progress and reproduction
methods: `labnotes/20260922-1420-sts-room-transcripts.md`.
Focused checkpoint: 93 startup, selection, room, input-policy and STS capability
tests pass (seed 0). These calls use an embedded PCM connection, not live carrier
or rendered WebRTC transport, and are not the final ten-concurrent-call load.

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
- [ ] The STS controller honors the existing contracts: policy-gated
  admission and revocation fencing, allowlist-shaped tool evidence (room
  authorization stays the owner's duty), readiness via `vxpipe_sts_ready`,
  generation-fenced cleanup, and explicit rejection of concurrent second
  sources (`:source_mismatch`) and unsupported handoff. Cancellation IDs
  survive until the matching result or cancellation settles.
  Reopened by independent review: existing revocation checks cover the
  human-to-agent direction, not revocation of agent-to-human output alone.
  Complete the directional egress/credit tasks below before closing this claim.
- [ ] Slice exit: real room interruption/hold/transfer tests prove one
  terminal turn outcome, zero stale queued playback, bounded command handling
  and cleanup after owner loss. Wider scenario and latency assessment stay
  deferred to final acceptance.

### D — STS plus agent-output STT

- [ ] A Morse variant declaring no output transcription fails selection
  without `output_speech_to_text` and yields exactly one agent transcript
  with it (selection rules proven in checkpoint A and unchanged).
  Real-call admission and both caller-transcript variants now pass in
  `sts_transcript_modes_test.exs`; output-STT enablement uses the STT registry,
  not a separate provider-settings namespace.
  Google output-STT registry/private startup wiring now passes synthetic-credential
  fake-wire checks. PCM negotiation and hosted output-route acceptance remain open.
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
- [ ] Exit: complete and interrupted turns, denied policy, STT failure, and
  slow consumer cases settle honestly. Interrupted output restarts the
  output STT so late text cannot leak into the next turn.
  Reopened by the delayed-final-after-timeout reproduction below; interruption
  restart alone does not establish timeout/finalization isolation.

#### Independent acceptance audit follow-up (2026-09-22)

Read-only Astra review at `5e7fed4c` passed 30 existing local tests and reported
six failing additional in-memory probes. These are diagnostic reproductions,
not native-call, root-suite or hosted acceptance. Parent review must preserve
each method as an automated regression before repair. Task/dependency review:
finish ordered tool evidence first; keep output-policy, recognizer isolation,
provider-controller ordering and sidecar startup/usage as coherent checkpoints.
No new provider advertisement or billable call is authorized by these tasks.

- [ ] Reproduce directional egress revocation: queue a Morse reply, retain
  human-to-agent audio, revoke only agent-to-human audio, and require sink
  interruption during both generation and drain. Fence queued output, return
  held provider credit, and settle exactly one terminal outcome; denied audio
  must not merely clear `active_output` and strand credit or turn state.
  - [x] Prove both policy-update entry points fence an admitted output when only
    agent-to-human audio is revoked, during generation and after generation
    while sink playback is queued. Keep permitted human input available.
  - [x] A denied credited chunk must be acknowledged/discarded and retire its
    admitted output; delayed generation completion and playback acknowledgement
    must not produce a second terminal event. Verify provider slot reuse.
  - [ ] Complete authorization of not-yet-admitted and queued provider replies
    across egress revoke/regrant, with bounded retirement and no later replay.
    Active-output fencing alone does not establish this separate admission gate.
- [ ] Reproduce recognizer cross-turn contamination with the stalling output-STT
  fixture: time out ONE, begin TWO, then deliver ONE's delayed final. Retire or
  correlate recognizer generations after timeout and finalization failure so
  TWO cannot publish `OLD FIRST REPLY`. Cover delayed endpoints and multiple
  recognition segments without assuming one endpoint per output.
  - [x] First isolate failure generations: recognition timeout, a finalization
    error from a still-live recognizer, and provider loss must retire the old
    allocation before any queued next reply is admitted. Verify old provider
    `DOWN`, replacement readiness and legitimate next-turn text; do not rely
    on providers always terminating themselves after a rejected finalization.
  - [x] Preserve the selected transcript source through bounded restart attempts.
    A failed restart must invalidate the old allocation immediately, retain
    failed recognition rather than silently fall back to STS transcripts, and
    fail the owning allocation explicitly when recovery is exhausted.
  - [ ] Prove bounded aggregation/settlement of multiple recognition segments
    within one generated reply and no delayed endpoint crossing a successful
    reply boundary. Failure-generation isolation alone does not close this gate.
- [ ] Complete output-STT adapter resolution through the existing registry,
  retain provider-private startup configuration, and negotiate matching PCM
  formats or use an explicit supported conversion. Prove synthetic-credential,
  fake-wire hosted-adapter startup and differing Morse STS/STT sample rates;
  reject unsupported combinations explicitly before allocating a live call.
  - [x] Reproduce Google STT rejection in the output-recognition slot; delegate
    adapter/options validation and host enablement to the existing STT catalog.
  - [x] Preserve recognizer-private credential/config/transport options separately
    from the STS generator in startup, then forward them through the existing
    room allocation PrivateInit handoff into the sidecar.
  - [x] Prove actual selected Google STT startup with synthetic credentials and
    a fake wire, matching 16 kHz fixture formats, and inspect/status redaction.
    Keep unavailable credentials, disabled hosts and invalid selections rejected.
  - [ ] Separately implement PCM negotiation/conversion or explicit mismatch
    rejection, including differing Morse STS/STT rates. Registry/private-config
    evidence alone does not complete this overall item or output-route acceptance.

  Registry/private-config design review (2026-09-22): output recognition is an
  existing STT capability used in a different slot, not a new provider manifest
  capability or credential namespace. Keep public provider tuples unchanged and
  retain private sidecar options in a dedicated redacted runtime field. The room
  allocation already has a separate PrivateInit handoff for the sidecar; reuse it
  without modifying capability/Output/Usage or shared speech internals. Format
  negotiation and finalization/turn acceptance remain separate follow-ups.
  Verification: five new focused checks and the 95-test startup/selection,
  unchanged room-transcript and Google adapter/session group pass (seed 0,
  two schedulers). Exact red-green methods are recorded in
  `labnotes/20260922-1721-output-stt-private-config.md`.
  Parent integration `4d786b0a` also passes the same 95-test group, after native
  Astra xhigh source review found no scoped defect. The normative provider
  contract is synchronized; post-commit broader evidence is separate in
  `labnotes/20260922-1746-sts-sidecar-integration.md`.
- [x] Separate output-STT usage identity, accepted-audio duration and terminal
  outcome from the STS generator. Reproduce a timed-out 16 kHz `stalling_stt`
  recognizer reporting `morse_code`, success, and 4,200 ms for 6,300 ms of
  accepted audio. Verify correct provider/rate attribution and failed outcome
  through persisted usage, not only internal capability state.
  - [x] Add focused regressions for the recognizer's own provider/model, accepted
    PCM duration at its selected rate, and timeout/finalization outcomes independent
    of successful STS playback. Include cancellation and rejected input accounting.
  - [x] Capture the ready recognizer's validated descriptor for each reply's usage;
    retain it across replacement, count only accepted input, and derive recognition
    success/failure/cancellation without borrowing the generator's context.
  - [x] Persist real capability observations through the ordinary archive/usage
    store and read back provider, duration and outcome; synchronize the provider
    contract and commit focused evidence before broader umbrella gates.
    - [x] Repair the newly reproduced persistence rejection: observation/amount
      schema enums, value decoding and database capability constraints must accept
      both STS and agent-output STT. Add an additive migration without editing the
      historical migration or deleting existing usage; verify actual writes and
      idempotent readback, not only the Calls archive projection.
    - [x] Emit STS usage timestamps at the archive's microsecond precision. The
      real retry reproduction stores a millisecond timestamp then rejects the
      identical fact because stored precision differs; preserve exact immutable
      fact comparison rather than changing generic archive deduplication here.
  - [x] Preserve completed recognition usage across a later idle recognizer loss
    while playback is pending. Independent review of `4f5d2fb1` identified that
    the failure handler retroactively overwrites an acknowledged successful final.
    Reproduce with the controlled stalling fixture, explicit final acknowledgement,
    provider `DOWN`/replacement readiness and delayed playback completion. Cover
    unfinished recognition failure separately; do not infer full multi-segment
    settlement from this completed-generation case.

  Usage checkpoint design review: descriptor identity and PCM rate belong to the
  selected recognizer; playback success does not prove recognition success. Reuse
  existing immutable usage observations and persistence, without new billing
  estimates or token inference. Hosted startup and PCM conversion remain the
  separate preceding task; this checkpoint measures bytes actually accepted.
  Focused evidence: 118 capability/room STS tests and four database usage tests
  pass (seed 0). Real timed-out recognition persists `stalling_stt`, failed and
  6,300 ms alongside successful STS playback, including identical-write retries.
  See `labnotes/20260922-1704-sts-recognizer-usage.md`. All five post-commit root
  gates at `4f5d2fb1` pass (2,282 tests, zero failures, 45 excluded, seed 0).
  Independent review reopened the later-idle-loss case above; its subsequent
  controlled red/green repair passes 119 focused STS tests and native Astra xhigh
  source re-review. See `labnotes/20260922-1718-sts-completed-recognition.md`.
  Multi-segment and hosted/lifecycle accounting remain separate acceptance work.

The audit also reproduced tool admission/result delivery under denied policy.
That reproduction is covered by the already-planned ordered-tool-envelope task
above: retaining an exact source/epoch alone is not current authorization.
Submitted invocation outcomes must still survive privately for later reasoning.

### E — Google Gemini 3.8 Live

#### Integrated provider follow-up tasks (2026-09-22 audit)

- [ ] Complete documented Google activity-wire/controller integration (codec
  evidence alone does not establish controller or streaming acceptance).
  - [ ] Verify official SDK server `voiceActivity` mapping for the selected
    Gemini v1beta transport, distinct from allowlisted detection signals and
    client `activityStart`/`activityEnd` fields.
  - [ ] Reproduce actual-payload decoding failures; validate activity enum and
    optional offset, and remove invented server-content activity fallbacks.
  - [ ] Migrate Google codec/session fixtures and verify focused tests without
    changing session/controller semantics or claiming hosted acceptance.

  Codec design review: decode top-level server activity into the existing private
  adapter events only. Unspecified activity creates no boundary; malformed known
  fields fail explicitly. Parent owns activity-end semantics and capability
  streaming admission. No controller, shared event or manifest changes belong here.
  Source-verification blocker: JS SDK 2.24.0 exposes `voiceActivityType`, but its
  generated converter reads raw `type` while the Gemini receive path bypasses
  that converter. Do not treat SDK-shaped fixture success as raw v1beta proof.
  Evidence/proposal: `labnotes/20260922-1736-google-voice-activity.md`.

- [ ] Drive the fake Google socket through the real STS capability/controller:
  send output transcript/audio/generation completion before server
  `turnComplete`, and prove early text survives and streaming output starts
  before the end of the response. Extend past 16 chunks with normal sink credit
  to distinguish correct streaming admission from unbounded buffering. Existing
  session tests manually arrange admission and do not prove this ordering.
  - [ ] Verify documented Google wire onset/end signals before reusing the existing
    fixtures. The decoder currently expects boolean `serverContent.activityStart`
    and `activityEnd`, while the official SDK exposes top-level `voiceActivity`.
    Prove the actual supported provider-control signal with a decoder/session/
    controller regression; neither a transcript nor model `turnComplete` may
    masquerade as caller speech onset/end. Record protocol availability limits
    explicitly and keep hosted selection gated. Both documented activity enum
    values currently decode to `{:ok, []}`; sources and exact read-only probe are
    in `labnotes/20260922-1721-sts-google-wire-audit.md`.
- [ ] Implement explicit output-transcript final settlement consistently with
  the descriptor: `Event.build(:output_transcript, ..., final: true)` currently
  rejects the event despite accepting `output_settlement: :transcript_end`.
  Test final/late/missing text and history reconciliation without fabricating
  played content or claiming the hosted history gate passed.
  - [x] Admit bounded output transcript snapshots with a boolean final marker;
    make Morse emit the explicit final its descriptor promises. Test the actual
    channel and capability boundary, not just struct construction.
  - [x] Require the selected descriptor's settlement evidence plus acknowledged
    generation completion and matching playback before publication. Exercise final
    text before/after playback, immutable final snapshots, and stale-turn rejection.
  - [x] Bound missing explicit finals with one validated, non-renewing deadline
    after generation completion; fail explicitly without publishing partial text.
    For generation-boundary providers, reject missing text at that boundary and
    prevent post-boundary replacement. Preserve independent output-STT settlement.
    - [x] Start that budget immediately at generation acknowledgement, before
      bounded sink finalization, and enforce absolute expiry when a queued final
      is handled. Reproduce deferred sink finish outlasting the budget followed
      by a late final; sink delay must not create a fresh transcript budget.
  - [ ] Separately prove interrupted provider-history reconciliation or explicit
    session failure; transcript settlement alone does not close that requirement.

  Settlement design review: output transcript events carry bounded cumulative
  snapshots, not engine-concatenated deltas. An explicit final freezes that
  snapshot; a declared generation boundary freezes the last prior snapshot.
  Playback remains a separate required fact. The explicit-final deadline starts
  once at acknowledged generation completion, never restarts on partial updates,
  defaults to five seconds and admits only positive bounded internal overrides.
  Timeout closes the uncertain allocation; it does not fabricate final text,
  switch transcript source, replay history or claim remote hearing.
  Focused evidence: initial ten event/controller tests had nine expected failures,
  plus the real Morse conversation failed its missing-final assertion. After
  implementation and the deferred-sink deadline repair, 133 focused STS
  event/capability/room tests pass, seed 0, including timer cancellation,
  different-turn/timeout isolation after hold and absolute deadline enforcement.
  See `labnotes/20260922-1751-sts-transcript-settlement.md`. Interrupted-history
  reconciliation and the overall Google controller gate remain unchecked.
- [x] Carry bounded private agent prompt and authorized tool schemas through
  STS activation configuration into initial and resumed Google setup. Reject
  unsupported configuration explicitly. Verify fake-wire setup contents; an
  injected function-call response is not evidence of provider tool discovery.
  - [x] Resolve the pinned prompt and allowed tool descriptors through the existing
    tool compiler; carry only model-visible fields in redacted private startup data.
  - [x] Validate Google instruction/declaration encoding against official sources;
    reject invalid, unsupported and oversized configuration before socket startup.
  - [x] Prove exact initial and handle-resumed fake-wire setup, empty tools, bounds,
    and inspect/status/log redaction with focused Call Engine red-green tests.
  - [x] Document local evidence and remaining gated selection/hosted acceptance.
  - [x] Integrate the reviewed private setup checkpoint with current STS runtime
    fixes, synchronize the normative provider contract and rerun focused tests
    before recording broader post-commit umbrella evidence.
  - [x] Repair adapter-local full-string tool-name validation after independent
    review of `dd501d39`: reject trailing newlines at construction and after
    private-config tampering, before fake-socket connection. Preserve the shared
    accepted name alphabet without sanitization or shared descriptor changes.

  Name-validation review: the shared descriptor's line-oriented anchors accept a
  final newline. Ordinary Call Spec validation rejects it, so the demonstrated
  defect is at the Google private-config boundary, not a permission bypass.
  Evidence: 36 Google codec/session checks first had two failures (constructor
  acceptance and malformed setup reaching a fake socket), then passed after an
  adapter-local full-string check. See `labnotes/20260922-1723-google-tool-name-validation.md`.

  Configuration design review (2026-09-22): reuse the private provider-init path
  and retained resumption config, without changing capability/room ownership or
  invoking tools/another model. Tool declarations must preserve authorized names
  and schemas, never serialize invocation bindings. Unsupported activation contexts
  fail explicitly. Google remains absent from the manifest; local tests exercise
  the startup configuration boundary directly without enabling production selection.
  Parent owns shared execution lifetime, normative-contract sync and final gates.

  Configuration evidence: 88 focused startup/selection, Google codec/session and
  shared STS conformance/output tests pass, seed 0, two schedulers. Initial and
  resumed setup contain the exact authorized JSON schemas and pinned instruction;
  malformed private setup fails before connecting. Unsupported MCP activation
  ownership fails explicitly, as do unavailable variable bindings and oversized
  configuration. See [Google configuration decision](../google-speech-integration.md#private-sts-activation-configuration)
  and `labnotes/20260922-1650-google-activation-config.md`. Public Google selection,
  hosted interoperability and overall milestone acceptance remain incomplete.
  Parent integration: `e5cb0993` and `13969fdc` preserve both reviewed checkpoints
  alongside the recognition-usage repairs. The integrated startup/Google/shared
  STS group passes 90 tests, zero failures, seed 0. Normative private-configuration
  requirements are synchronized in `docs/speech-provider-contract.md`.
  Post-commit umbrella verification is recorded separately; neither this group
  nor the earlier umbrella run substitutes for the open Google controller tests.
  All five post-commit root gates at `9ffe2ab4` pass: 2,299 tests, zero failures,
  45 excluded, seed 0 (including 1,139 Call Engine and 492 Gateway tests).
  See `labnotes/20260922-1733-sts-google-integration.md`. Later private-policy and
  sidecar changes require their own integration evidence; final gates stay open.
- [ ] Add the tagged hosted controller/interruption/resumption acceptance check
  before requesting billable execution. Keep it excluded by default and Google
  unadvertised until the separately authorized acceptance gate passes.

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

#### Google output-credit follow-up tasks (2026-09-22)

Inspection found that `Google.STSOutput.buffer_audio/2` caps the pre-admission
buffer at 16 chunks but appends without a bound once output is admitted. This
does not satisfy the same bounded-output contract under a slow consumer.

- [x] Prove the existing 16-pending-chunk limit also applies to an admitted
  output whose consumer holds its single audio credit. Cover the limit exactly,
  the first rejected chunk, FIFO order, and capacity released by acknowledged
  delivery. Keep the existing wire PCM size/framing validation.
- [x] Enforce that shared limit in both buffer states. Fail the owned session
  on overflow through its existing safe failure path; do not drop arbitrary
  generated speech, allocate a second queue, or reconnect/replay to hide loss.
- [x] Preserve every validated PCM byte when splitting a large wire audio part.
  Inspection found the fixed-size binary comprehension discards a non-full
  tail after a 131,072-byte chunk. Add a non-multiple-length PCM regression,
  require exact concatenation and bounded/even chunks, then repair splitting
  without increasing wire message or output-chunk limits.
- [x] Exercise the fake-socket/session/channel path with withheld credit,
  requiring explicit failure and supervised cleanup. Rerun Google protocol,
  resumption and shared output conformance checks; commit before broader gates.
  No hosted calls, manifest enablement, public configuration or new timeout.
- [x] Update the author guide with the implemented buffer/tail guarantees and
  correct its stale claim that the transport microphone path is unconnected.
  Preserve the distinction between native input tests and full native call
  acceptance; documentation must not overstate either checkpoint.

Design/dependency review: the Google adapter owns its provider-ahead-of-credit
queue; the channel owns the one outstanding audio credit. Reuse the existing
16-chunk contract rather than increasing buffering. This check is independent
of public caller-turn design and does not close hosted or lifecycle acceptance.
Evidence: pure buffer/codec tests first failed on unbounded active buffering,
opening a full pre-admission buffer, and lost PCM tails (11 tests, three failures).
The fake-socket credit test separately reproduced a non-terminating overflow;
all 43 Google protocol/resumption and shared STS output/conformance checks now
pass, seed 0. After commit `3b1fa264`, all five umbrella gates pass: 2,205 tests,
zero failures, 42 excluded, seed 0. See
`labnotes/20260922-1453-google-sts-output-bounds.md`.

### F — Service UI, documentation, and final acceptance

- [x] Synchronize the normative `docs/speech-provider-contract.md`, not only
  this checklist and the author guide (user clarification, 2026-09-22):
  - [x] Correct historical migration status and callback coverage against the
    implemented behaviours; label original research as historical evidence.
  - [x] Specify STS-owned sessions, directional PCM, response/transcript-source
    separation, consumer-authorized output credit, room-owned public identity,
    egress-qualified transcript settlement, and safe interruption/overflow.
  - [x] Require bounded pre-admission and active buffering and lossless PCM
    rechunking; distinguish Google's concrete limits from universal requirements.
  - [x] Document private Google handle-based resumption with no historical audio
    replay or fresh-session fallback, and keep hosted support/unfinished room
    contracts explicitly gated. Verify local links and source/test references.

  Documentation review/evidence: `labnotes/20260922-1500-provider-contract-sync.md`.
  This synchronizes the contract; it does not accept pending room/tool, native,
  lifecycle, hosted, load, UI or final-review tasks.

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
- [x] Run a bounded local synthetic load (at most about half the machine's
  resources) comparing current LLM + TTS calls with Morse STS and STS + STT.
  Measure admission/startup, input acceptance, speech onset, first audio,
  playback acknowledgement, turn completion, interruption and failure
  isolation p50/p95/p99 plus drops, mailbox growth and cleanup. Pause and
  investigate any proven new call/app instability before shipping.
  - [x] Implement a dedicated, reproducible tagged lane with ten barrier-synchronized
    pinned room calls per mode: fixture LLM + Morse TTS, Morse STS provider
    transcript, and Morse STS + agent-output STT. Use allowed room PCM input,
    public events and a bounded, clock-paced synthetic playback sink.
  - [x] Test harness-owned bounds, percentile calculation and playback accounting
    red/green; cap schedulers, run duration, turns, retained samples and PCM.
  - [x] Collect measured admission/startup, input acceptance, speech onset, first
    audio, playback acknowledgement, completion, interruption and isolated failure
    timings, dropped input/output, sampled mailbox growth and monitored cleanup.
    - [x] Wire Morse STT's existing optional ingress-owner notifications to a
      bounded harness observer and reconcile delivered/dropped/rejected input.
      The room's default nil observer supplies no drop evidence; absence of
      notifications must not be reported as a measured zero.
  - [x] Smoke-test the lane under contention; record defects before any runtime
    repair. Dedicated harness scope excludes STS/provider runtime changes.
  - [x] Run the integrated ten-call comparison only in a parent-scheduled quiet
    window; retain p50/p95/p99 reports and review isolation/cleanup evidence before
    completing load acceptance. Contended smoke output is not performance evidence.
  - [x] Repair harness timing attribution before integration: record input origin
    before feeder spawn; bind caller/public/sink IDs independently to immutable
    input origins; gate barge-in on all phase-two onset evidence and reject
    unknown/duplicate correlation. Add a deterministic sink-before-public-onset
    regression and uniquely named test supervisors; rerun focused/smoke checks.
    Evidence: `labnotes/20260922-1636-fence-load-attribution.md`; seven focused
    contracts and all three two-call smoke modes pass. The subsequent quiet
    ten-call measurement is recorded below.
  - [x] Make the harness sink stale-finish regression deterministic: replace
    scheduler-sensitive interrupt/clear timing assertions with controlled clock
    and captured timer tokens, explicit stale-token injection and acknowledgement
    barriers. Retain pure PCM arithmetic tests and actual paced smoke coverage.
    Same review checkpoint evidence: seven focused tests and three real-paced
    two-call modes pass; no scheduler-relative interrupt/clear assertion remains.

  Load harness design review (2026-09-22): allocation-only conformance is insufficient;
  each mode must pass actual admitted room audio and public completion. Synthetic
  sink playback describes paced PCM consumption, never human hearing. Final load
  acceptance depends on integrated lifecycle behavior and a quiet measurement window.
  Harness evidence: [method and commands](../sts-comparative-call-load.md) and
  `labnotes/20260922-1610-comparative-call-load.md`. Three two-call smoke modes
  pass; each observes five complete turns, two interruptions and one healthy
  post-fault call. The subsequent coordinated ten-call run at `5792d797` passes
  all three modes in 25.3 seconds, with no rejected/dropped input. Each mode
  completes 29 turns, ten interruptions, nine healthy post-fault survivors and
  cleanup of all ten calls. Full measured distributions and sample counts are
  in the linked methodology/results; coordination and environment evidence are
  in `labnotes/20260922-1657-sts-ten-call-measurement.md`. This closes the bounded
  local load checkpoint, not hosted/native/UI/lifecycle acceptance. Repeat after
  remaining material runtime changes in the final coordinated acceptance pass.
  Parent integration at `9908a1a1` also passes all seven harness contract tests
  and all three two-call modes against the latest tool, recognizer and egress
  fixes. Root static gates pass; full umbrella remains pending. Review/integration evidence:
  `labnotes/20260922-1650-sts-load-integration.md`.
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
