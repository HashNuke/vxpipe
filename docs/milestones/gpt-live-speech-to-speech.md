# GPT-Live speech-to-speech

Status: specification frozen on 2026-09-25; checkpoints A and B are implemented
and verified. Checkpoint C is partially implemented: the capability's
provider-owned barge-in branch and the room's `:overlapped` outcome are in
place, while the compiled-room duplex proof and the remaining C fixtures,
checkpoint D (OpenAI package and GPT-Live adapter), checkpoint E (session
continuity) and checkpoint F (docs, Console gating, hosted check, load, review)
are not started. Change the specification only through a recorded amendment in
this section, with its reason; for example, a checkpoint A finding that
contradicts an assumption below. The milestones index entry stays unchecked
until the acceptance checks below pass.

Prerequisites: [Agent speech-to-speech](agent-speech-to-speech.md) (the
provider-controlled STS contract, room publication and Morse STS) and
[Tenant-scoped provider credentials](tenant-provider-credentials-and-platform-configuration.md).

Design sources: [speech provider contract](../speech-provider-contract.md),
[speech integration guide](../speech-integration-guide.md),
[STS output admission](../sts-output-admission.md),
[STS context restoration](../sts-context-restoration.md), OpenAI's
[GPT-Live session guide](https://developers.openai.com/api/docs/guides/live-conversations)
and [delegation and tools guide](https://developers.openai.com/api/docs/guides/live-delegation).

## Runnable outcome

A call spec can select `provider: "openai"`, `model: "gpt-live-1"` for an agent's
`speech_to_speech` capability. The caller talks to the agent over any existing
room transport. The room publishes one caller turn and one agent turn per
utterance, releases agent text only for audio that was played locally, runs
allowlisted tools, keeps its conversation across a hold, and survives a provider
session ending by starting a new session seeded from the room's own transcript
history. The call behaves like a natural phone conversation (see below). Every
ordinary test
runs against a local Morse duplex provider and a fake GPT-Live socket; the
hosted check is opt-in and billable.

## Why GPT-Live needs its own profile

Gemini Live and OpenAI Realtime report conversational events: turn completion,
generation completion and interruption. GPT-Live does not. Its WebSocket
session is full duplex:

- `session.input_transcript.delta` and `session.output_transcript.delta` carry
  a text fragment plus `start_ms`/`end_ms`, milliseconds from session start.
  The guide states that transcript deltas have no item ID and no event that
  marks a completed conversational turn; the application groups them.
- `session.output_audio.delta` carries audio with no timing fields.
- Tools run through delegation. With Responses delegation, function calls
  arrive inside `response.event` envelopes; every pending call needs a
  `response.item.create` result before one `response.create` continues.
  Instructions can redirect speech but do not cancel backend work.
- `session.usage.updated` reports cumulative voice duration in seconds; backend
  model and tool usage is billed separately.
- `session.closed` reports `close_requested`, `expired`, `content`,
  `remote_hangup` or `connection_lost`. There is no resumption handle. A new
  session can be seeded with text history (at most 128 messages and 8,192
  tokens at startup).

The current STS contract assumes provider-declared turn boundaries, one
admitted output per provider turn, and a room that can interrupt the provider.
This milestone keeps a single room-facing contract. The GPT-Live adapter infers
turns and segments its output into the existing event vocabulary, and new
descriptor facts tell the room how far to trust that evidence and who owns
barge-in. The room gains no GPT-Live-specific code.

## Phone call behaviour

This milestone covers caller-to-agent phone calls. Every design choice below is
judged against how a person behaves on a phone call:

- **Talking over.** A listener's "uh-huh" or "yeah" does not stop the speaker;
  a real interruption does. The model decides whether to yield, so
  backchannels do not cut the agent off.
- **Response timing.** The model decides when to answer. Inferred turn
  boundaries only label the transcript and call record; they never trigger,
  delay or block a response.
- **No clipped speech.** Agent audio is never discarded in a way that clips a
  word onset, and the local playback buffer stays short so a yield is heard
  promptly.
- **Hold.** The agent keeps its conversation and any lookup in progress, knows
  the caller cannot hear it, and resumes naturally ("thanks for waiting")
  without reconnect delay.
- **Dropped connection.** Recovery is quick. If the agent was mid-answer or the
  caller was waiting for an answer, the agent picks up where it left off;
  otherwise it waits for the caller.
- **Echo.** On a phone line, the agent's own voice can return through the
  caller's audio. An always-listening model must not react to its own speech;
  this is verified on real carrier calls.

## Contract changes

### Descriptor facts

Closed admission facts on the STS descriptor, validated with the existing
descriptor rules. Existing STS providers declare the first value in each row.

| Fact | Values | GPT-Live |
| --- | --- | --- |
| `endpointing` (existing field) | add `:inferred_gap` | `:inferred_gap` |
| `output_shape` | `:turns`, `:continuous` | `:continuous` |
| `barge_in` | `:room`, `:provider` | `:provider` |
| `continuity` | `:resumption_handle`, `:history_reseed`, `:none` | `:history_reseed` |
| `tool_cancellation?` | `true`, `false` | `false` |
| `hold` | `:stop`, `:mute` | `:mute` |
| `history_reconciliation?` (existing) | unchanged | `false` |

Validation rules:

- `:inferred_gap` is valid only with provider turn control and `speech_start?`.
- `barge_in: :provider` requires `history_reconciliation?: false`: the room has
  no truncation operation to call.
- `:continuous` output requires the adapter to segment it (below); the room
  never receives a continuous output stream.
- `:history_reseed` requires the provider to accept seeded text history at
  session start.
- `hold: :mute` requires a provider operation that stops input audio while the
  session and its backend work continue, and a way to give the model context
  without prompting speech.

### Events

- `:turn_ended` accepts `endpointing: :inferred_gap`. The room carries that
  evidence label onto the public `ParticipantTurnCompleted` event, so an
  inferred boundary is never presented as a provider-declared one.
- `:output_transcript` gains optional `output_ref`, `audio_start_ms` and
  `audio_end_ms`: the fragment's span inside that admitted output, measured
  from the output's first byte. The provider timeline stays private to the
  adapter. Providers that cannot align fragments omit these fields and keep the
  existing turn-level settlement.
- The public agent turn gains an `:overlapped` outcome for `barge_in: :provider`:
  the caller spoke while the agent's output was playing and the provider chose
  whether to yield. `:interrupted` remains reserved for a room-initiated fence.

### Room and capability behaviour

- `Capability.SpeechToSpeech` currently fences active output on every provider
  `:speech_started`. Make that conditional on `barge_in: :room`. With
  `barge_in: :provider`, caller onset opens the caller turn but leaves output
  playing; the room still fences output for policy denial, hold, transfer and
  teardown.
- When fragment spans are present, the spoken agent text for a fenced or
  overlapped output is the fragments whose `audio_end_ms` is at or before the
  locally played duration. Later fragments are dropped, not published.
- Hold and caller-to-agent policy revocation with `hold: :mute` keep the
  session. The capability mutes provider input, fences and discards output
  locally while held, and gives the model context: on hold, that the caller is
  on hold and cannot hear it; on release, that the caller is back and nothing
  said during the hold was heard. The session stops only when the agent leaves
  the call, for example after a completed transfer, or on teardown.

### Usage

- Map `session.usage.updated` to voice duration in the existing `:milliseconds`
  unit, as deltas per provider session. The final figure comes from
  `session.closed`. Each reseeded session starts a new cumulative count.
- Report backend Responses usage (`response.completed` token counts) under a
  separate usage identity for the backend model.

## Adapter design

All inference is provider-private. Put the provider-neutral parts in pure
modules under the speech namespace so the Morse duplex provider and the
GPT-Live adapter share them. Durations are counted in audio time, never wall
clock, so tests need no timers or sleeps.

### Caller turn inference (`Speech.Duplex.TurnInference`)

Inferred caller turns are for publication and records only. They never
trigger, delay or block the model's response.

- Open a caller turn on the first input fragment: emit `:speech_started` and
  partial `:input_transcript`.
- Close it when either condition holds:
  - pushed caller audio since the last input fragment reaches the gap; or
  - a new input fragment's `start_ms` exceeds the previous `end_ms` by more
    than the gap.
- On close, emit the final `:input_transcript`, then `:turn_ended` with
  `:inferred_gap`.
- The gap is a validated provider option, default 800 ms: long enough to span
  the provider's roughly 200 ms fragment cadence and ordinary pauses.

### Output segmentation (`Speech.Duplex.OutputSegmenter`)

- An energy gate over output PCM opens a burst above an activation threshold
  and closes it after the gap of audio below a deactivation threshold.
  Thresholds are relative to the provider's silence floor, a validated option.
- The gate only marks turn boundaries. It must never clip speech: retain a
  pre-roll (default 300 ms) of the most recent sub-threshold audio and send it
  at the start of each burst, and forward pauses inside a burst unchanged.
- On open, call `Session.admit_output/2` with a fresh output reference; forward
  the pre-roll and the burst's audio through the existing credited path; on
  close, emit `:output_completed`. Silence between bursts, before the pre-roll
  window, is not forwarded; the transport's own silence fills the line.
- The provider streams at real-time pace and has no flow control. Keep the
  local playback queue short so a model yield is heard promptly; the separate
  receive buffer (default 2 s of audio) only absorbs network jitter, and
  overflow fails the session with an explicit reason rather than blocking the
  socket.
- Align output fragments to bursts: the first fragment of a burst fixes the
  offset between the provider timeline and that output's audio; later fragments
  get `audio_start_ms`/`audio_end_ms` relative to the output. A fragment whose
  audio already played is attached to that earlier output. A fragment with no
  matching audio after a bounded amount of further output (default 3 s) is
  dropped and counted, never published as spoken text.

### Tools (Responses delegation only)

- Declare only the agent's allowlisted function tools in
  `delegation.responses.tools`, with a pinned backend model option. Reject
  provider-hosted tools such as `web_search`.
- Emit `:tool_call` only for a nested `response.output_item.done` item of type
  `function_call` with status `completed` and a call ID, name and arguments.
  Keep the delegation ID and call ID private; deduplicate by call ID.
- `send_tool_result` sends `response.item.create` with a
  `function_call_output`. Send one `response.create` only when the delegation
  has no pending calls.
- `tool_cancellation?: false`: interruption and overlap do not cancel an
  invocation. The room runs it to completion or its existing deadline, and the
  result is still returned.
- A `response.failed` or `response.incomplete` discards that delegation's
  pending calls; a later result for one is not sent to the provider.

### Session continuity

- Set `store: false` explicitly. Forking and stored sessions are out of scope.
- If the session duration limit is documented, renew before it: start the
  replacement at the first quiet point (no open caller turn and no active agent
  burst) inside a renewal window, and switch over without an audible gap.
- On `expired` or `connection_lost`, start at most one replacement session
  within a bounded deadline, seeded with the room's published transcript
  history truncated from the oldest end to the provider's startup limits. Only
  text is seeded; no audio is replayed and nothing unheard is presented as
  heard. Failure to reseed in time fails the capability explicitly.
- After a reseed, if the drop interrupted an agent reply or came after a
  completed caller turn that had no reply yet, ask the model to continue: say
  briefly that the line cut out and carry on from the last heard text.
  Otherwise the new session waits for the caller.
- `close_requested` and `remote_hangup` are ordinary ends; `content` fails the
  capability with an explicit moderation reason.
- Delegated backend work belongs to the lost session. Invocations the room
  already started still finish under their existing deadlines; their results
  are given to the new session as context.

### Text input

`push_text` maps to `session.commentary.append` (spoken) for opening messages
and explicit "speak now" requests. It still passes the existing proactive-output
gate. Standing instructions use `session.instructions.append` within its token
limit. Hold, release and reconnect context uses `session.thinking.append`, which
informs the model without prompting speech.
The existing opening-message behaviour applies.

## Morse duplex provider

`Vxpipe.Providers.MorseCode.DuplexSTSSession` is a credential-free local
provider that behaves like GPT-Live, so the default suite exercises the same
room paths without a billable service. It is a separate module from the
existing Morse STS session and reuses the Morse tone codec.

- Declares the GPT-Live descriptor facts above.
- Streams continuous, clock-paced PCM output including silence.
- Emits timed input and output fragments on its own session timeline, with no
  turn, generation or interruption events.
- Uses the shared `TurnInference` and `OutputSegmenter` modules.
- Yields by itself: when it decodes caller tone during its own output, it stops
  that reply, as a provider-owned barge-in.
- Offers a delegated tool-call shape (call, result, continue) and no
  cancellation.
- Supports input mute and context-only appends for hold tests.
- Reports cumulative voice duration and supports scripted `expired` and
  `connection_lost` closes for reseed tests.

## Checkpoints

### A — Verified API profile and contract facts

- [x] Verify against the official API reference and record in
  `docs/sts-duplex-profile.md`: WebSocket URL and authentication,
  `session.start` fields (model, voice, `audio.format`, instructions, history,
  delegation, `store`), supported WebSocket audio formats and rates, the session
  duration limit, whether output audio includes continuous silence, how the
  model behaves when talked over, and error/close semantics. Mark each item
  documented or unverified. Unverified behaviour becomes a hosted-check item,
  not an assumption.
- [x] Red-green the descriptor facts and validation rules above, including
  rejection of each invalid combination and unchanged Gemini and Morse STS
  descriptors.
- [x] Red-green the event additions: `:inferred_gap` evidence, aligned
  `:output_transcript` fields, and the `:overlapped` outcome.
- [x] Exit: the contract compiles and validates; existing STS suites pass
  unchanged.

Evidence (2026-09-25): `docs/sts-duplex-profile.md` records the documented
facts and six residual unverified items for checkpoint F (extra connection
headers, nonstandard `audio.format`, talk-over/echo, continuous output silence,
any numeric duration limit, and 24 kHz down-conversion). The profile documents
the primary WebSocket output audio as untimed and the sideband-only reflected
`start_ms`/`end_ms`, so the adapter cannot rely on wire output timing.

`Speech.Descriptor` gains closed `output_shape`, `barge_in`, `continuity`,
`tool_cancellation?` and `hold` facts plus an `:inferred_gap` endpointing value.
Defaults are the first value in each table row, so Gemini and Morse STS
descriptors are unchanged; non-STS descriptors must keep the defaults.
`:inferred_gap` is valid only for `turn_control: "provider"` with
`speech_start?`, and `barge_in: :provider` requires
`history_reconciliation?: false`.

`Speech.Event` accepts `endpointing: :inferred_gap` on `:turn_ended` and
`:eager_turn_ended`, and optional `output_ref`/`audio_start_ms`/`audio_end_ms`
alignment on `:output_transcript` (present only as a complete, ordered span).
`AgentTurnCompleted` carries an `outcome` (`:completed | :overlapped`, default
`:completed`) and `ParticipantTurnCompleted` carries optional `endpointing`
evidence; both are projected into the archive payload.

Verification: `sts_duplex_contract_test.exs` (9 tests, red then green) plus
unchanged `descriptor_test.exs`/`event_contract_test.exs`. Full
`vxpipe_call_engine` suite passes 1,523 tests, 0 failures, 30 excluded (seed 0),
and the Gateway `turn_state` group passes 5 tests. `mix compile
--warnings-as-errors` is clean. One earlier combined-suite run had a single
timing failure in `speech_to_text_test.exs:496` that passes in isolation; it is
the pre-existing load-sensitive STT timing behavior, not this contract change.

### B — Shared duplex modules and Morse duplex provider

- [x] Red-green `TurnInference` on fixture fragment sequences: quiet-audio
  close, timeline-gap close, overlapping speakers, empty fragments and a
  session end while a turn is open.
  Evidence: `test/vxpipe/call_engine/speech/duplex/turn_inference_test.exs`
  (7 tests, red then green) covers all five fixtures against the pure module in
  `lib/vxpipe/call_engine/speech/duplex/turn_inference.ex`.
- [x] Red-green `OutputSegmenter` on PCM fixtures: burst open and close, pauses
  shorter than the gap, silence discarded, fragment alignment, late fragments,
  unmatched fragments and buffer overflow.
  Evidence: `test/vxpipe/call_engine/speech/duplex/output_segmenter_test.exs`
  (9 tests, red then green) covers every listed fixture against
  `lib/vxpipe/call_engine/speech/duplex/output_segmenter.ex`, including the
  pre-admission receive-buffer overflow and the quiet-onset pre-roll.
- [x] Implement `MorseCode.DuplexSTSSession` and prove it through the STS
  capability: one caller turn, one aligned agent reply, self-yield on caller
  tone, delegated tool call and result, and a usage report.
  Evidence: `Vxpipe.Providers.MorseCode.DuplexSTSSession` over
  `Provider.MorseCodeDuplex.Session` shares `TurnInference` and
  `OutputSegmenter` and reuses the Morse codec. Capability test
  `test/vxpipe/call_engine/capability/speech_to_speech_duplex_test.exs` (3
  tests) proves one caller turn → one segmented reply, playback-settled
  `"RECEIVED HI"` transcript, a `:milliseconds` `:speech_to_speech` usage
  observation, and `TOOL echo {...}` → result → `"RECEIVED ok"` reply.
  `test/vxpipe/call_engine/speech/duplex_sts_conversation_test.exs` proves
  provider self-yield deterministically: while one output credit is held,
  caller tone makes the provider finish the interrupted reply (its
  `:output_completed` follows the released credit) without any engine fence.
- [x] Exit: capability-level tests pass without any provider socket.
  `capability` + `speech` suites pass 504 tests, 0 failures (seed 0). The
  `barge_in: :provider` capability branch (caller onset leaves output playing)
  is implemented here and proven by checkpoint C below.

### C — Room integration

Partial: the capability's `barge_in: :provider` branch and the room's
`:overlapped` outcome are implemented and the existing room suites stay green.
The compiled-room duplex proof and the remaining C fixtures are open.
See [review 1](#review-1--2026-09-25), finding R1-1: the branch needs its
failing test before any other C work.

- [ ] Red-green the capability's barge-in branch: with `barge_in: :provider`,
  caller onset leaves output playing; policy denial, hold and teardown still
  fence it. Existing `barge_in: :room` tests stay green.
  Implemented in `Capability.SpeechToSpeech.handle_event/2` (caller onset with an
  active output returns without fencing when the descriptor declares
  `barge_in: :provider`). Existing `capability` + `speech` suites pass 504 tests
  with the change. A focused red test that injects caller onset while an output
  is held open is still needed to close this box.
- [ ] Prove compiled room calls with the Morse duplex provider: one caller and
  one agent turn per utterance, `:inferred_gap` evidence on the public caller
  turn, and agent text published after playback settlement. Open.
- [ ] Prove overlap: the caller speaks during the reply, the provider yields,
  the agent turn ends `:overlapped`, and its published text stops at the last
  fragment whose audio played. Prove a short backchannel during the reply does
  not stop playback.
  Partial: the room now labels an overlapped agent turn `:overlapped`
  (`AgentTurnCompleted.outcome`, default `:completed`) and inferred caller
  boundaries carry their evidence onto `ParticipantTurnCompleted`. Focused room
  tests `room_authority/speech_to_speech_test.exs` prove both outcomes. The
  compiled-room overlap and per-fragment truncation remain.
- [ ] Prove a soft word onset below the activation threshold is played in full
  through the pre-roll. Open (the pure `OutputSegmenter` proof exists in B).
- [ ] Prove hold with `hold: :mute`: input is muted, output is discarded while
  held, the model receives hold and release context, a tool started before the
  hold delivers its result after it, and release resumes without a new session.
  Open.
- [ ] Prove a room fence mid-reply publishes only the aligned spoken prefix and
  zero-playback fences publish none. Open.
- [ ] Prove a tool invocation survives overlap and its result reaches the
  provider. Open.
- [ ] Exit: room tests pass for all of the above plus unchanged Gemini and
  Morse STS room suites. Open.

### D — OpenAI provider package and GPT-Live adapter

- [ ] Add `Vxpipe.Providers.OpenAI` with a tenant API-key credential through
  the existing tenant credential readers. The manifest does not advertise
  `:sts` until checkpoint F.
- [ ] Implement `Vxpipe.Providers.OpenAI.GPTLiveSession` and a private socket
  under the agent capability tree: `session.start`, audio append and output
  decoding, fragment handling through the shared modules, and PCM format
  negotiation or explicit rejection.
- [ ] Drive a fake GPT-Live socket from JSON fixtures through the real STS
  capability: caller and agent turns, overlap, delegated tools (including
  multiple pending calls, duplicates, and failed or incomplete responses),
  usage deltas, every close reason, and malformed-event failure.
- [ ] Prove no credential, audio or transcript appears in logs, status or crash
  reports.
- [ ] Exit: fake-socket tests pass; no hosted call has been made.

### E — Session continuity and lifecycle

- [ ] Red-green reseed on `expired` and `connection_lost`: seeded history comes
  from room-published, playback-fenced transcripts, is truncated to the
  startup limits, and starts a new usage count.
- [ ] Prove post-reseed speech: a drop mid-reply or after an unanswered caller
  turn makes the new session continue; a drop while idle leaves it waiting.
- [ ] If a duration limit is documented, prove renewal at a quiet point before
  it with no audible gap.
- [ ] Prove reseed failure and deadline expiry fail the capability explicitly.
- [ ] Prove a completed transfer and teardown stop the session, and a failed
  transfer releases the hold with the same session, with both Morse duplex and
  the fake socket.
- [ ] Exit: lifecycle tests pass with both local providers.

### F — Service gating, documentation and acceptance

- [ ] Update the speech provider contract, integration guide (with an author
  example for the duplex profile) and provider-package docs.
- [ ] Add a gated OpenAI GPT-Live option to the Console setup catalog; the
  badge stays disabled until the hosted check passes.
- [ ] Add a tagged hosted check, run only with explicit authorization for
  billable use and a fixed short budget, over a real Twilio or Telnyx phone
  leg: a short turn, a backchannel and a real interruption during a reply, a
  tool call, a hold and release, a forced reconnect with reseed, and speakerphone echo without the agent reacting
  to its own voice. Resolve every item left unverified in checkpoint A.
- [ ] Inspect the Console change in a rendered browser at desktop and mobile
  widths.
- [ ] Run the bounded ten-call local load lane with the Morse duplex provider.
- [ ] Run an independent implementation review and all root completion checks.
- [ ] Enable the manifest `:sts` entry and service badge only after the hosted
  check passes.

## Scope boundaries

Out of scope for this milestone:

- Outbound agent-to-person calls; the platform does not place them yet. When
  they are added, the agent must wait for the callee to answer and speak before
  greeting, without talking over ringing or pickup.
- WebRTC transport to OpenAI (server-side WebSocket only).
- Client delegation and `session.delegation.created` handling beyond rejecting
  it explicitly.
- Stored sessions, forking and recording download (`store: false`).
- Provider-hosted tools, including `web_search`.
- Agent-output STT and external or hybrid turn control.
- OpenAI Realtime, which reports turn and interruption events and fits the
  existing provider-events profile; it can be added as its own adapter.

## Alternatives considered

- **Room-side turn inference.** Rejected: the room would need GPT-Live-specific
  timing rules, and every other provider would carry that code. Inference
  belongs to the adapter, which declares it through descriptor facts.
- **Room-initiated barge-in for GPT-Live.** Rejected: the model cannot be
  interrupted or truncated, so clearing local playback cuts the agent off
  mid-word while it keeps talking and its history assumes the words were heard.
- **Publishing agent text per session-timeline fragment without alignment.**
  Rejected: the playback fence needs fragments positioned inside an admitted
  output.
- **Stopping the session on hold and reseeding on release.** Rejected: the
  caller returns to reconnect silence, in-progress backend work is lost, and the
  agent does not know a hold happened. Muting keeps the conversation; hold and
  release context tells the model that nothing said while held was heard.
- **Forwarding only audio above the energy gate.** Rejected: it clips quiet word
  onsets. The gate marks boundaries; pre-roll keeps onsets intact.
- **Always waiting for the caller after a reseed.** Rejected: a drop mid-answer
  would leave both sides silent.

## Specification review

Drafted on 2026-09-25 from OpenAI's GPT-Live session and delegation guides and
inspection of two open-source GPT-Live client implementations. Both infer
caller turns from roughly 0.8 s of quiet, derive agent speech from output
audio, and leave barge-in to the model. Checkpoint A later verified the
documented API facts in `docs/sts-duplex-profile.md`; the remaining unverified
items belong to the hosted check. This is a design review, not implementation
or hosted evidence.

## Implementation reviews

Reviews are numbered and append-only. Each records the reviewed state (base
commit plus whether the worktree was dirty), what was verified, findings with
stable IDs, and the next order of work. A later review never edits an earlier
one; it reports each earlier open finding as resolved (with evidence), still
open, or withdrawn (with reason). Reviews are not acceptance evidence.

### Review 1 — 2026-09-25

Reviewed state: base `9ad1b79a` on `sts2` with uncommitted A, B and partial C
work, after the implementation run paused.

Verified:

- The 48 new and changed duplex, contract, capability and room tests pass
  (`speech/duplex/`, `duplex_sts_conversation_test.exs`,
  `sts_duplex_contract_test.exs`, `speech_to_speech_duplex_test.exs`,
  `room_authority/speech_to_speech_test.exs`; seed 0). The reported full
  umbrella run (2,731 tests, zero failures) was not repeated in this review.
- `docs/sts-duplex-profile.md` separates documented API facts from unverified
  ones and moves the unverified items to the checkpoint F hosted check, as
  checkpoint A requires. The frozen specification changed only in its status
  and evidence notes.
- The pause came at a green, honestly reported boundary.

Findings:

- R1-1 — **Untested behaviour change.** The `barge_in: :provider` branch in
  `Capability.SpeechToSpeech.handle_event/2` was implemented before a failing
  test existed, contrary to the project's red-green rule. Before any other C
  work, write the focused test that holds an output open, injects caller onset
  and fails without the branch; then confirm policy denial, hold and teardown
  still fence the output.
- R1-2 — **Stated reasons for pausing are not blockers.** The run cited remaining
  budget and multi-day scope, but 42% of its context was used. Only the
  checkpoint F hosted check needs outside authorization (billable use and
  real carrier legs); C, D and E are local work.
- R1-3 — **Checkpoint order.** Finish C before D. C is half done and carries the
  untested change above; its compiled-room proofs with the Morse duplex
  provider are the room behaviour every later checkpoint relies on. D (the
  OpenAI package and adapter over a fake socket) follows C's exit.
- R1-4 — **Prerequisite still open.** This milestone depends on
  [Agent speech-to-speech](agent-speech-to-speech.md), which is unchecked and
  awaiting scope decisions. Building GPT-Live ahead of it is out of index
  order; the user decides whether to continue in parallel.

Open findings: R1-1, R1-3, R1-4. R1-2 needs no code change.

Next work, in order: the R1-1 test; the remaining C tasks; C's exit;
then D. Pause only at the hosted check or for a recorded blocker.
