# Agent speech-to-speech

Status: full A–F scope selected; implementation has not started. Every
implementation and acceptance box below is open.

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

- [ ] Add a failing Call Engine test for the three valid agent modes, illegal
  STS + LLM/TTS combinations, per-participant transcript-source requirements,
  turn-control selection independent of those sources, and unchanged
  published specs. Add `speech_to_speech` to call-spec/resolved structs,
  compiler, catalog, startup and inspection/usage schema where needed. Add
  the explicit `output_speech_to_text` agent selection and reject accidental
  inheritance from human STT defaults.
- [ ] Add a failing independent-provider conformance test, then implement
  `STSProvider`, descriptor/event/channel rules, bounded commands, identity
  fencing, activity/text-settlement/history capabilities, and provider
  manifest `:sts` support. Update provider and speech author docs with exact
  callback, event, configuration, and error contracts.
- [ ] Exit: local contract/compile tests prove unsupported providers fail
  closed and old LLM + TTS selection still runs. No STS service badge yet.

### B — Morse STS with provider transcript

- [ ] Add a failing room test for one human audio turn producing Morse audio
  and an agent-attributed transcript, including policy denial, no mixed-audio
  echo, source mismatch, mid-turn policy revocation, transcript-route denial,
  hold, and teardown. With human STT selected, assert its text is the sole
  caller transcript and causes no text-model `SendText` dispatch or duplicate
  response. Without human STT, assert STS input text is the sole caller
  transcript and fails admission if unavailable.
- [ ] Implement `Provider.MorseCodeSTS.Session` plus its private tone/text
  codec, an agent-owned STS capability tree, bounded input/output, room
  audio/sink wiring, public turn events, and egress-fenced transcript
  routing. Make it available only to credential-free local configurations.
- [ ] Slice exit: focused room tests prove Morse reply, attributed transcripts,
  redaction, no cross-room state and unchanged LLM + TTS behavior. Defer the
  integrated real local call and wider verification to final acceptance.

### C — Interruption, tools, and transfer lifecycle

- [ ] Add failing Morse tests for human speech onset during output, queued
  playback, zero-playback interruption, late and corrected audio/text,
  provider interruption, proactive output, text input, tool call/cancellation,
  room hold, agent transfer, and owner death. Cover provider, human-STT-driven,
  and supported hybrid response triggering independently of the caller
  transcript source; no duplicate responses. Submit a tool, interrupt speech,
  then prove its one result is available to the next turn without reviving the
  old response. Prove prompt onset without human STT or reject that selection
  until a separate activity detector is available.
- [ ] Connect the STS controller to existing RoomAuthority interruption,
  allowlisted tools, variables, readiness, first-message/opening, private
  briefing, transfer and cleanup APIs. Retain tool cancellation IDs until
  settled. Reject unsupported source handoff explicitly.
- [ ] Slice exit: focused local call and transfer tests prove one terminal turn
  outcome, zero stale queued playback, bounded command handling and cleanup
  after owner loss. Defer wider scenario and latency assessment to final
  acceptance.

### D — STS plus agent-output STT

- [ ] Add a failing Morse variant that declares no output transcription.
  Assert that selection without `output_speech_to_text` fails and selection
  with it yields one agent transcript, never a caller transcript or duplicate
  text.
- [ ] Feed credited STS output into an agent-scoped semantic STT allocation,
  with explicit finite-input finalization at the STS generation boundary,
  bounded fanout, policy attribution and playback fencing. Extend the STT
  provider contract with a bounded finite-input operation/descriptor only if
  needed by the selected adapter; keep human conversational onset and turn-end
  requirements intact. Update the STT author guide for agent-output usage.
- [ ] Exit: complete and interrupted turns, denied policy, STT failure, and
  slow consumer cases settle honestly. The provider-transcript path remains
  independently green.

### E — Google Gemini 3.8 Live

- [ ] Add failing fixture-driven tests for setup, voice, PCM conversion,
  multi-part message parsing, out-of-order transcripts/audio, generation versus
  playback completion, interruption before first audio, selected turn-control
  mode, tool cancellation, `goAway`, resumption, expiry and unsafe/missing resumption
  handle. Exercise sent-ahead-of-playback interruption and subsequent model
  context; gate the adapter if unheard speech changes the next reply.
- [ ] Implement `Vxpipe.Providers.Google.STSSession` and private `STSSocket`
  under the existing Google package. Resolve saved credentials privately,
  enable output transcription, and declare STS in the manifest only when
  local room/contract checks pass. No parallel old socket or fallback.
- [ ] Slice exit: focused fixture/contract tests pass and the adapter remains
  unadvertised. Defer the tagged hosted check to the coordinated final pass;
  run it **only after explicit authorization for billable use**. Without that
  check, leave Google production selection and its badge gated.

### F — Service UI, documentation, and final acceptance

- [ ] Implement gated Google `s2s` support in the backend service-binding
  capability response and Console setup catalog/card tags/model choices;
  Morse remains a local test option. Extend the service/recipe, tenant and
  platform views without creating a second Google credential entry. Add
  focused frontend tests now; keep the badge disabled until final hosted
  acceptance, and defer the rendered desktop/mobile pass to that final pass.
- [ ] Update `docs/provider-integration-packages.md`,
  `docs/speech-provider-contract.md`, `docs/speech-integration-guide.md`,
  call-spec/API examples and operator guidance for all three modes. Document
  transcript provenance and the lack of automatic fallback. Reconcile the
  milestone/index checklist with actual evidence.
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
  Mark the index complete only after all applicable acceptance gates.

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
