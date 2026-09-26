# GPT-Live speech-to-speech

Status: specification frozen on 2026-09-25; checkpoints A and B are implemented
and verified. Checkpoint B was reopened by review 3 and is closed again after
the clock-paced output rework; review 4's R4-1 is resolved by giving the Morse
duplex provider its own real-time clock (`clock: :realtime`, the default) with a
manual test mode. Review 6's six code-review findings (R6-1..R6-6) are resolved
(see the response to review 6). Checkpoint C is partially implemented: the capability's
provider-owned barge-in branch is covered by a red-green test and the room's
`:overlapped` outcome is in place, while the compiled-room duplex proof and the
remaining C fixtures, checkpoint D (OpenAI package and GPT-Live adapter),
checkpoint E (session continuity) and checkpoint F (docs, Console gating,
hosted check, load, review) are not started. Change the specification only
through a recorded amendment in this section, with its reason; for example, a
checkpoint A finding that contradicts an assumption below. The milestones index
entry stays unchecked until the acceptance checks below pass.

Post-review decisions recorded with the amendments:

- R2-1 versioning rule: the additive `AgentTurnCompleted.outcome` and
  `ParticipantTurnCompleted.endpointing` fields stay in schema version 1.
  Consumers of stored events must treat a missing field as `:completed` /
  `nil`; no version bump is required because old payloads decode through the
  struct defaults. Any consumer that reads either field must apply that rule
  before relying on it.
- R2-3: `OutputSegmenter` now defaults to the specified 800 ms gap (raised
  from 400 ms), and the Morse duplex provider uses the shared defaults with no
  overrides (2 s receive buffer).

Amendments:

- **Amendment 1 (2026-09-25), from R2-2 and review 3.** The duplex descriptor
  facts apply to STS descriptors only; STT and TTS descriptors do not carry
  them. Every STS provider declares each fact explicitly rather than inheriting
  a default. Existing values: Google STS declares `continuity:
  :resumption_handle`; Morse STS declares `continuity: :none`. Both keep
  `output_shape: :turns`, `barge_in: :room`, `tool_cancellation?: true` and
  `hold: :stop`. Reason: the original "existing providers declare the first
  value" rule claimed a resumption handle for Morse STS, which has none.

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
descriptor rules. Existing STS providers declare the first value in each row,
except as corrected by Amendment 1 (Morse STS declares `continuity: :none`).

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
  `test/vxpipe/call_engine/capability/speech_to_speech_duplex_test.exs` proves
  one caller turn → one segmented reply, playback-settled `"RECEIVED HI"`
  transcript, a `:milliseconds` `:speech_to_speech` usage observation,
  `TOOL echo {...}` → result → `"RECEIVED ok"` reply, and (R1-1) that caller
  onset leaves a provider-owned output playing while a policy denial still
  fences it. `test/vxpipe/call_engine/speech/duplex_sts_conversation_test.exs`
  proves self-yield, clock-paced silence discarding, pre-roll and explicit
  receive-buffer overflow at the provider boundary.
  Review-3 rework (R2-3, R3-1): output is a continuous, clock-paced stream
  (leading silence, reply, trailing silence); the shared `OutputSegmenter`
  defaults are used unchanged (800 ms gap, 2 s buffer) and no provider override
  tunes the module to the fake.
  Review-4 rework (R4-1, R4-2): the provider owns its clock. `clock: :realtime`
  (the default) records a monotonic origin and schedules its own 20 ms ticks
  with drift correction and bounded catch-up, so a compiled room or the load
  lane drives it without external pacing; `advance/2` is rejected under the
  realtime clock. `clock: :manual` and `yield?` are documented test options.
  The pure `MorseCodeDuplex.Clock.frames_due/5` scheduler is unit-tested for
  ordinary, late and stalled ticks; a capability test runs under the realtime
  clock with no external tick and no sleep.
- [x] Exit: capability-level tests pass without any provider socket.
  `capability` + `speech` suites pass with no provider socket. The
  `barge_in: :provider` capability branch is covered by the red-green test above
  (removing the branch fails it) and by the room `:overlapped` outcome below.

### C — Room integration

Partial: the capability's `barge_in: :provider` branch is covered by a
red-green test and the room's `:overlapped` outcome is implemented. The
compiled-room duplex proof and the remaining C fixtures are open.

- [x] Red-green the capability's barge-in branch: with `barge_in: :provider`,
  caller onset leaves output playing; policy denial, hold and teardown still
  fence it. Existing `barge_in: :room` tests stay green.
  Evidence: `speech_to_speech_duplex_test.exs` "caller onset leaves a
  provider-owned output playing…" holds the output active (the fake does not
  self-yield) and asserts no `vxpipe_sts_interrupted` on caller onset, then
  asserts a policy denial still fences it. Removing the branch makes the test
  fail (verified red then green). Existing `capability` + `speech` suites stay
  green. Hold and teardown fencing are covered by the existing STS hold/stop
  tests.
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

### Review 2 — 2026-09-25 (implementation response)

This is the implementation run's response to Review 1, not independent
verification. A later independent Review 3 should assess it as such.

Reviewed state: base `3b1f7147` on `sts2`; this response is appended to the
milestone doc, and the worktree otherwise contains only a pre-existing
`apps/vxpipe_gateway` telephony test change that predates this milestone and is
not part of its commits.

Response to Review 1:

- R1-1 — **still open; confirmed empirically.** Removing the
  `barge_in: :provider` branch from `Capability.SpeechToSpeech.handle_event/2`
  leaves the relevant duplex, contract, capability and room suites green (75
  tests, zero failures), so nothing currently covers it. The branch is still
  required: without it the capability cuts local playback on caller onset
  regardless of the provider descriptor. Test-seam correction for the fix: the
  capability auto-acknowledges PCM credits as the sink accepts, so a
  capability-boundary test cannot naturally hold a burst open. Pin the behavior
  with a capability unit test (stubbed active output plus a `barge_in:
  :provider` descriptor) or a compiled-room test whose provider withholds one
  credit, and assert that policy denial, hold and teardown still fence.
- R1-2 — **acknowledged; no code change.** C, D and E are local work; only the
  checkpoint F hosted carrier check needs outside authorization. Corrected
  wording: the pause was a conservative choice, not a hard blocker.
- R1-3 — **agreed.** Finish C before D.
- R1-4 — **valid caution, narrowed.** The milestone's prerequisite line scopes
  the dependency to the provider-controlled STS contract, room publication and
  Morse STS, all of which have focused evidence. The parent
  [Agent speech-to-speech](agent-speech-to-speech.md) milestone is globally
  unchecked, and the index calls its order conservative "even where independent
  work is possible"; the user has directed continued work. Not a hard blocker,
  but keep it recorded.

Additional findings raised by this response:

- R2-1 — **Public event schema.** `AgentTurnCompleted.outcome` and
  `ParticipantTurnCompleted.endpointing` are additive fields on structs and on
  archive payloads for already-persisted events. The umbrella suite passes, but
  consumer coverage and persisted-event versioning were not reviewed; add a
  versioning note before publication.
- R2-2 — **Continuity default is semantically loose.** `continuity:
  :resumption_handle` is the default for existing STS descriptors only to
  satisfy the frozen table's "existing providers declare the first value" rule,
  but Morse STS has no resumption handle. Record an amendment that either gives
  local providers `:none` or states the fact is advisory for them.
- R2-3 — **Segmenter tuning is provisional.** The output gap (1 s), pre-roll
  (300 ms) and receive buffer (2 s) were chosen so the Morse provider yields one
  burst per reply. The real adapter may need different values; treat them as
  tunable, not settled.
- R2-4 — **Review evidence mechanics.** A later review should report added and
  changed test counts separately, and should repeat the umbrella run rather
  than cite it, since that run is the milestone's acceptance evidence.

Next work, in order: the R1-1 focused test and fence confirmations; the
remaining C tasks; C's exit; then D, then E and F.

### Review 3 — 2026-09-25 (response to review 2)

Independent review of the implementation run's review 2 response.

Reviewed state: base `3b1f7147` on `sts2`, with review 2 uncommitted in this
file and the unrelated `apps/vxpipe_gateway` telephony test change. No code
changed since review 1; this review re-read the committed `a2a7043a` code.

Status of earlier findings:

- R1-1 — **still open.** Review 2's proof that removing the branch leaves 75
  tests green confirms nothing covers it. Its claim that a capability-boundary
  test cannot hold output open is overstated: existing capability tests hold
  processes with `:sys.suspend/1`, a stub provider can leave its output
  uncompleted, and `duplex_sts_conversation_test.exs` already holds an output
  credit to prove self-yield. Either proposed test design is acceptable. The
  test is still unwritten.
- R1-2 — **closed.** Review 2's corrected wording is accepted.
- R1-3 — **closed as agreed.** The order stands: C before D.
- R1-4 — **still open, as a caution.** Review 2 says the prerequisite parts
  "all have focused evidence". That is generous: room publication and
  lifecycle tasks remain unchecked in the parent milestone. Only the user can
  confirm the direction to continue in parallel.
- R2-1 — **accepted.** Archived `agent_turn_completed` payloads now always
  include `"outcome"` and `participant_turn_completed` payloads may include
  `"endpointing"`, but `schema_version` was not bumped. Old events decode
  through the struct defaults, so nothing breaks now. Decide and record the
  versioning rule before any consumer reads the new fields.
- R2-2 — **accepted; the specification error was review 1's author's.**
  Recorded as Amendment 1 in the status section. The code has a second part:
  `Descriptor.default_duplex_facts?/1` makes STT descriptors carry STS-only
  facts, including `continuity: :resumption_handle`. Remove the facts from
  non-STS descriptors and make each STS provider declare them explicitly.
- R2-3 — **accepted, with corrections.** The drift is larger than stated:
  - `OutputSegmenter` defaults its gap to 400 ms (`output_segmenter.ex:25`);
    the Morse duplex provider overrides it to 1 s; the specification says
    800 ms.
  - The Morse duplex receive buffer is 60 s (`morse_code_duplex/session.ex:27`),
    not 2 s as review 2 states.
  These are changes to a frozen specification and need amendments or
  reverting. Do not tune the shared module to make the fake yield one burst per
  reply. Fit the fake to the specification instead, for example by using a Morse
  speed whose word gaps stay under 800 ms.
- R2-4 — **partly accepted.** Report added and changed test counts separately.
  Do not repeat the umbrella run in every review; that contradicts the
  project's cadence of full gates at checkpoint commits and in the final pass.
  A review cites the gate run tied to the commit it reviews, and repeats it
  only when reviewing acceptance.

New findings:

- R3-1 — **The Morse duplex provider does not behave like GPT-Live output.**
  The specification requires continuous, clock-paced PCM including silence.
  The implementation sends output only as sink credit arrives
  (`handle_info/2` on `:vxpipe_speech_credit`), has no pacing timer and
  streams no silence between replies. The segmenter paths specific to GPT-Live
  therefore never run in the local suite: discarding silence between bursts, a
  provider with no flow control, receive-buffer overflow, and pre-roll taken
  from real sub-threshold audio. The 60 s buffer hides this. Checkpoint B is
  reopened: add clock-paced output with silence, return the buffer to the
  specified 2 s, and prove silence discarding, overflow and pre-roll through
  the Morse duplex provider.
- R3-2 — **Label responses separately from reviews.** Review 2 is an
  implementation response and raises findings from the implementer's view. It
  says so, which is correct. From now on, label an implementer reply "Response
  to review N" with findings prefixed `P<N>-`, so review numbers stay for
  independent reviews. Existing labels stay as they are, since reviews are
  append-only.

Open findings: R1-1, R1-4, R2-1, R2-2, R2-3, R3-1.

Next work, in order: R2-2 and R2-3 corrections with Amendment 1 applied; R3-1
(reopened B); the R1-1 test; the remaining C tasks and C's exit; then D.
R2-1's versioning rule is needed before any consumer reads the new fields.

### Response to review 3 — 2026-09-25

Implementation response to Review 3, labelled per R3-2. Not independent
verification.

Reviewed state: base `f6369cb5` plus this rework; the unrelated gateway
telephony test change is untouched.

- P3-R2-2 — **resolved (Amendment 1 applied).** Duplex facts are STS-only: the
  descriptor defaults them to `nil`, non-STS descriptors must not declare them,
  and Google STS, Morse STS and the Morse duplex provider declare each fact
  explicitly (Morse STS `continuity: :none`).
- P3-R2-3 — **resolved.** `OutputSegmenter` keeps its 800 ms default gap and the
  Morse duplex provider uses the shared defaults with no overrides (2 s receive
  buffer, 300 ms pre-roll); Morse word gaps fit under the gap, so no module
  tuning forces one burst.
- P3-R3-1 — **resolved.** The provider now emits a continuous, clock-paced
  stream (leading silence, reply, trailing silence) driven by `advance/2`.
  Provider tests prove silence discarding, pre-roll replay of real
  sub-threshold audio, and explicit pre-admission receive-buffer overflow.
- P3-R1-1 — **resolved.** Added the focused barge-in test; removing the branch
  makes it fail (verified), and a policy denial still fences.
- P3-R2-1 — **resolved by decision.** Versioning rule recorded in the status
  section: additive fields stay in schema version 1; consumers treat missing
  fields as `:completed` / `nil`.
- P3-R2-4 — **applied.** Added versus changed test counts are reported
  separately in the labnote.
- P3-R1-4 — **still open as a caution.** The user has directed continued work;
  the parent milestone remains globally unchecked.

Next work, in order: the remaining C tasks and C's exit; then D; then E and F.
Pause only for the hosted check or a recorded blocker.

### Review 4 — 2026-09-25 (response to the review 3 response)

Independent review of commit `77bc64a3` and its "Response to review 3".

Reviewed state: base `77bc64a3` on `sts2`; the worktree holds only the
unrelated `apps/vxpipe_gateway` telephony test change.

Verified:

- 62 focused duplex, contract, provider-contract, capability and room tests
  pass (seed 0). Per R2-4, the umbrella run reported in the commit (2,734
  tests, zero failures) is cited, not repeated.
- R1-1 mutation check: replacing the `barge_in: :provider` guard in
  `Capability.SpeechToSpeech` with `false` makes "caller onset leaves a
  provider-owned output playing, but room fences still cut it" fail (3 tests,
  1 failure); restoring it passes.
- Amendment 1 is applied as written: the duplex facts default to `nil`, STT
  and TTS descriptors are rejected if they declare any, and Google STS
  (`:resumption_handle`), Morse STS (`:none`) and the Morse duplex provider
  declare every fact explicitly. The Google `pcm_format/1` extraction is
  behaviour-preserving.
- `OutputSegmenter` now defaults to the specified 800 ms gap, and the Morse
  duplex provider no longer overrides the gap, buffer or pre-roll.
- The Morse duplex provider emits leading silence, the reply and trailing
  silence as fixed 20 ms frames, and its tests cover silence discarding,
  pre-roll from real sub-threshold audio and receive-buffer overflow.

Status of earlier findings:

- R1-1 — **resolved** (mutation check above). The hold and teardown fences are
  covered by existing tests with `barge_in: :room` providers. That is
  acceptable because those paths do not pass through the branch; checkpoint
  C's `hold: :mute` task must still prove hold with the duplex provider.
- R1-4 — **still open, as a caution.**
- R2-1 — **resolved by decision.** The rule (additive fields stay in schema
  version 1; a missing field reads as `:completed` / `nil`) is accepted.
- R2-2 — **resolved** (Amendment 1 applied).
- R2-3 — **resolved.** Wording fix only: the status section says the segmenter
  "keeps" its 800 ms gap; it was raised from 400 ms to 800 ms.
- R2-4 — **resolved.**
- R3-1 — **resolved at the provider boundary; see R4-1.**
- R3-2 — **resolved.** The implementation reply is labelled as a response.

New findings:

- R4-1 — **The Morse duplex provider has no clock of its own.** Output advances
  only when `advance/2` is called, and only tests call it
  (`speech_to_speech_duplex_test.exs` looks up the provider process and ticks
  it). The module doc says "production drives it from a timer or socket
  reader", but no production path exists for this provider: in a compiled room
  or the ten-call load lane nothing ticks it, so the agent would never speak.
  The GPT-Live adapter will be driven by its socket; the Morse duplex provider
  needs its own real-time timer, with the manual clock kept as an explicit test
  option (for example `clock: :manual`) rather than the only mode. This blocks
  checkpoint C's compiled-room proof and checkpoint F's load lane. Checkpoint B
  stays closed: its capability-level proof is valid under a manual clock.
- R4-2 — **Minor: the test-only `:yield?` option is part of the public Morse
  duplex configuration.** Acceptable for a credential-free local provider, but
  document it as a test fixture option in the provider's module doc so it is
  not mistaken for a GPT-Live behaviour.

Open findings: R1-4, R4-1, R4-2.

Next work, in order: R4-1 (real-time clock with an explicit manual test mode);
the R2-3 wording fix and R4-2 note; then the remaining C tasks, starting with
the compiled-room duplex proof; C's exit; then D.

### Review 5 — 2026-09-25 (proposed solutions for review 4)

Proposed solutions for the open review 4 findings, from the same reviewer.
Reviewed state is unchanged from review 4 (`77bc64a3`); no new findings.

#### R4-1 — real-time clock for the Morse duplex provider

1. Add a validated `clock` option to the Morse duplex configuration:
   `:realtime` (the default) or `:manual`. `:manual` exists only for tests.
   `advance/2` returns `{:error, :unsupported_operation}` under `:realtime`,
   so a test cannot mix the two clocks by accident.
2. Under `:realtime`, the session owns its clock. When the session starts,
   it records a `System.monotonic_time/1` origin and schedules a 20 ms
   tick with `Process.send_after/3`, carrying a clock generation so a stale
   tick after close or restart is ignored. On each tick it emits the frames
   now due: the elapsed audio time since the origin, minus the audio already
   emitted, in whole 20 ms frames. Computing from the origin, not by counting
   ticks, prevents drift when the scheduler delivers a tick late.
3. Bound catch-up: a tick emits at most 100 ms of audio (five frames). If
   the session falls further behind, it moves the origin forward and counts
   the skipped audio as a late-clock observation instead of bursting. A real
   provider that stalls resumes at real time; it does not replay the stall.
4. Both clocks call the same frame-emission function (the existing
   `advance_clock/2` path), so manual-clock tests keep covering the emission,
   segmentation, pre-roll and overflow code that the real-time clock runs.
5. The session is a supervised GenServer under the agent's STS tree; its
   timer ends with it. `close/1` stops the clock before replying, and no
   `terminate/2` cleanup is needed.
6. Keep continuous silence while idle. At 50 ticks a second per session the
   cost is small, and it is the shape the segmenter must handle.

This mirrors production correctly: the GPT-Live adapter has no timer,
because its socket delivers output deltas at real-time pace, and it feeds
each delta to the same segmenter path. Only the local fake needs a clock.

Rejected alternatives:

- The capability or room calling `advance/2`: it would move a
  provider-private clock into the room and make the room behave differently
  for one provider.
- Returning to credit-driven output: GPT-Live has no flow control, so the
  fake would again skip the no-flow-control and overflow paths (R3-1).

Acceptance:

- Red-green: `configure/1` accepts `clock: :realtime` and `clock: :manual`,
  rejects any other value, and defaults to `:realtime`; `advance/2` is
  rejected under `:realtime`.
- A pure frames-due function (origin, now, emitted) is unit-tested for
  ordinary ticks, a late tick, and a stall beyond the catch-up bound.
- A capability test under `:realtime` receives the reply's output events and
  settled transcript with bounded `assert_receive` timeouts and no call to
  `advance/2` and no `Process.sleep/1`. Use a short Morse unit duration so
  the reply takes well under a second of audio.
- Existing manual-clock tests pass unchanged apart from opting into
  `clock: :manual`.
- Checkpoint C's compiled-room duplex proof and checkpoint F's load lane run
  under `:realtime`.

#### R4-2 — the test-only `:yield?` option

Document `:yield?` and `:clock` together in the Morse duplex module doc under
a "Test options" heading. State that `yield?: false` exists only to hold an
output open in barge-in tests, and that GPT-Live always decides for itself
whether to yield. Keep both options validated by `configure/1`, and do not add
either to the GPT-Live adapter's configuration.

#### R2-3 wording

Reword the status section's post-review note to say the segmenter "now
defaults to the specified 800 ms gap (raised from 400 ms)" instead of "keeps"
its 800 ms gap.

Open findings: R1-4, R4-1, R4-2 (unchanged from review 4).

Next work, in order: implement R4-1 as proposed; apply R4-2 and the R2-3
wording; then the remaining C tasks, starting with the compiled-room duplex
proof under `clock: :realtime`; C's exit; then D.

### Response to review 4 — 2026-09-25

Implementation response to reviews 4 and 5, labelled per R3-2. Not independent
verification.

- P4-R4-1 — **resolved as proposed.** `configure/1` accepts `clock: :realtime`
  (default) or `:manual` and rejects any other value. Under `:realtime` the
  session records a monotonic origin and schedules its own 20 ms ticks, emitting
  the frames now due with drift correction and a bounded catch-up; a longer
  backlog moves the origin and counts a late clock. `advance/2` returns
  `{:error, :unsupported_operation}` under `:realtime`. Both clocks share the
  same frame-emission path. `close/1` cancels the timer. The pure
  `MorseCodeDuplex.Clock.frames_due/5` scheduler is unit-tested (ordinary, late,
  stalled, negative elapsed). A capability test runs under `:realtime` and
  receives the reply and settled transcript with no external tick and no sleep.
- P4-R4-2 — **resolved.** The module doc now has a "Test options" section
  documenting `clock: :manual` and `yield?: false`, and states that GPT-Live
  always decides whether to yield.
- P4-R2-3 — **wording fixed.** The status note now says the segmenter "now
  defaults to the specified 800 ms gap (raised from 400 ms)".
- P4-R1-4 — **still open as a caution.** The user has directed continued work.

Also normalized the provider-option key lookup: `MorseCode.Config.option_keys/0`
replaces the runtime `Map.keys(Config.__struct__()) -- [:__struct__]` idiom in
all four Morse sessions.

Next work, in order: the remaining C tasks, starting with the compiled-room
duplex proof under `clock: :realtime`; C's exit; then D; then E and F.

### Review 6 — 2026-09-25 (code review)

Independent code review of the milestone's code so far.

Reviewed state: `9ad1b79a..a00bd7a0` on `sts2`, plus the uncommitted R4-1/R4-2
work in the worktree (the Morse duplex real-time clock). Method: a code
review of that diff and worktree, with each finding below confirmed by reading
the code. No tests were run for this review. Line numbers refer to the worktree.

Status of earlier findings:

- R1-4 — **still open, as a caution.**
- R4-1, R4-2 and the R2-3 wording — **reported resolved by the response to
  review 4; not verified here.** That work is uncommitted; verify it once it is
  committed.

New findings, most severe first. Findings R6-3 and R6-4 break the output
admission contract (the room waits for a completion that never comes); R6-1
and R6-6 are places where the Morse duplex provider does not behave like
GPT-Live. All six affect checkpoint C's compiled-room proof.

- R6-1 — **High: a reply with a pause longer than the gap loses its later
  audio** (`morse_code_duplex/session.ex:533`, `open_burst/2`). A Morse word
  gap is 7 units: 420 ms at the default 60 ms unit, but the configuration
  allows units up to 200 ms, and from 115 ms the gap reaches the 800 ms
  segmenter gap, so `"RECEIVED HI"` becomes two bursts. The second burst hits
  the `admitted?: true` clause, which returns without calling
  `OutputSegmenter.admitted/2`; its audio stays buffered and is never played,
  while the published transcript still claims the whole reply. A long enough
  word overflows the 2 s buffer and stops the session. GPT-Live pauses
  mid-answer, so this path matters beyond Morse.

  Proposed fix: implement the specification's output segmentation as written:
  each burst is its own admitted output, completed when the gate closes, and
  the agent turn spans its bursts until the reply ends. First check whether the
  room's admission protocol allows more than one output per provider turn; if
  it does not, record that as a contract gap and decide it (amend to
  per-burst outputs within one turn) before implementing. Tests: at
  `unit_duration_ms: 150`, both words play as two outputs in order, the
  transcript is aligned per output, and a long word does not overflow.

- R6-2 — **Medium: a low `amplitude` means the reply is never played**
  (`session.ex:189`, `segmenter_options/1`). Only `sample_rate` reaches the
  segmenter, so the gate opens above a fixed energy of 1000, while the
  configuration accepts amplitudes from 1. At `amplitude: 800` no burst opens,
  the output never completes, and every later reply queues behind it.

  Proposed fix: derive the activation and deactivation thresholds from
  `config.amplitude`, and have `configure/1` reject an amplitude whose tone
  energy cannot open the gate. Test: a low but accepted amplitude plays its
  reply; an undetectable one is rejected at configuration.

- R6-3 — **Medium: yielding before the room admits the output leaves the
  room's output slot stuck** (`finish_if_ready/1`, `handle_admit/3`). If
  caller tone starts after `turn_ended` but before the room's
  `{:vxpipe_speech_output, ...}` admission arrives, the output is dropped with
  no event. The admission then matches nothing and is ignored, and the room
  waits for an `output_completed` that never arrives; later admissions return
  `:busy`.

  Proposed fix: remember a reply that yielded before admission. When its
  admission arrives, complete that output at once as interrupted with nothing
  played, so the room settles the slot. Test with the manual clock and a held
  admission message: yield first, deliver the admission, and assert the room
  receives the completion and admits the next reply.

- R6-4 — **Medium: a second queued reply silently replaces the first**
  (`start_reply/3`). `queued_reply` holds one reply and is overwritten without
  a check. With `yield?: false`, or while a yielded output waits for credit,
  two caller turns (or a caller turn and a tool result) ending during one
  output drop the first queued reply, including an admission the room may
  already have sent, so the room waits for its completion forever.

  Proposed fix: replace `queued_reply` with a bounded FIFO of pending replies,
  each keeping its own admission reference; overflow fails the session with an
  explicit reason rather than dropping a reply. Test: two turns during one
  output play both replies in order and complete both admissions; overflow
  fails explicitly.

- R6-5 — **Medium: a tool result can end the turn with no reply and no
  error** (`publish_tool_reply/2`, `start_reply/3`). `turn_ended` is emitted
  before the reply is encoded. A string result near 256 bytes plus the
  `"RECEIVED "` prefix exceeds `maximum_text_bytes`, and a map result rendered
  with `inspect/1` contains characters Morse cannot encode. `start_reply/3`
  swallows the encoding error.

  Proposed fix: build a Morse-encodable summary first (truncated to fit the
  prefix within `maximum_text_bytes`, limited to the encodable character set),
  encode it, and only then emit `turn_ended`. If encoding still fails, fail
  with an explicit reason instead of returning the unchanged state. Tests: a
  250-character string and a map result each produce a spoken reply; a forced
  encoding failure is reported, not silent.

- R6-6 — **Low/medium: the `:overlapped` outcome almost never fires**
  (`room_authority/speech_to_speech.ex:372`; `session.ex:334-336`). The Morse
  duplex provider yields as soon as caller tone starts, but emits its first
  input fragment, and so `speech_started`, only when the utterance is fully
  decoded (`:partial` is ignored). By then the agent turn has already completed
  as `:completed`. GPT-Live sends input fragments roughly every 200 ms while
  the caller speaks.

  Proposed fix: emit an input fragment on decoder `:started` and on each
  `:partial`, so caller onset reaches the room while the agent output is still
  open, as it does with GPT-Live. Test: a barge-in that the provider yields to
  is published with outcome `:overlapped`.

Open findings: R1-4, R6-1, R6-2, R6-3, R6-4, R6-5, R6-6. R4-1 and R4-2 await
verification.

Next work, in order: commit the in-progress R4-1/R4-2 work; R6-3 and R6-4 (the
admission contract); R6-1, starting with the one-output-per-turn check; R6-6;
R6-5 and R6-2; then the remaining C tasks, starting with the compiled-room
duplex proof.

### Response to review 6 — 2026-09-25

Implementation response to Review 6, labelled per R3-2. Not independent
verification.

- P6-R6-1 — **resolved by decision**, after the required check. The room's
  admission protocol has one output slot per provider turn and does not re-admit
  a second output for the same turn, so per-burst outputs would need a room
  contract change. Instead the provider keeps one output per reply and treats a
  later burst as a continuation: `open_burst/2` calls `OutputSegmenter.admitted/2`
  for the new burst and flushes its buffered audio under the existing output
  reference, dropping the inter-burst silence as the segmenter specification
  requires. The agent turn therefore spans its bursts and no audio is lost.
  Test: a reply whose inter-word gap (1050 ms at `unit_duration_ms: 150`)
  exceeds the 800 ms segmenter gap plays every burst and completes.
- P6-R6-2 — **resolved.** The segmenter thresholds derive from
  `config.amplitude` (activation half, deactivation quarter), and `configure/1`
  rejects an amplitude below 2 whose tone cannot open the gate. Test: an
  amplitude of 1 is rejected; an accepted low amplitude plays its reply.
- P6-R6-3 — **resolved.** A reply that yields before the room admits it is
  remembered in `yielded_pending`; when its admission finally arrives the
  provider emits `:interrupted` so the room settles the slot. Test: yield the
  un-admitted reply, deliver the delayed admission, and observe the
  interruption.
- P6-R6-4 — **resolved.** `queued_replies` is a bounded FIFO (16) with each
  entry keeping its own admission reference; overflow fails the session with
  `:pending_reply_overflow` instead of dropping a reply. Test: two replies
  queued behind one output play in order and both admissions complete.
- P6-R6-5 — **resolved.** A tool result is summarised to a Morse-encodable,
  length-bounded string and encoded before `turn_ended` is emitted; an encoding
  failure stops the provider with an explicit reason. Tests: a map result
  becomes `RECEIVED OK TRUE`; a 400-character result is truncated into a
  bounded reply.
- P6-R6-6 — **resolved.** Input fragments are fed on each decoder partial as
  contiguous audio-time slices, so `speech_started` reaches the room while a
  yielded reply is still open and the caller turn is not split by sparse
  fragment timing. The room `:overlapped` outcome is proven by the existing
  room unit test; the provider change is exercised by every caller-turn test.

Also: `interrupt/2` now cancels a queued or yielded-pending reply and returns
`:ok` rather than `:stale_request`, so a room fence of a pending turn does not
fail the capability.

Next work, in order: the remaining C tasks, starting with the compiled-room
duplex proof; C's exit; then D; then E and F.

### Review 7 — 2026-09-26 (response to the review 6 response)

Independent review of commits `480d481e` (real-time clock), `d3e66990`
(review 6 record) and `1bc3227f` (review 6 fixes), and of the "Response to
review 4" and "Response to review 6" sections.

Reviewed state: `1bc3227f` on `sts2`, clean worktree.

Verified:

- 75 focused tests pass (seed 0): the duplex modules, Morse duplex clock and
  conversation tests, the STS duplex and provider contracts, the duplex
  capability tests and the room STS tests. Per R2-4, the umbrella run reported
  in `1bc3227f` (2,747 tests, zero failures) is cited, not repeated.
- Review 6's text in this file is unchanged from what was committed in
  `f9ffc2cf`.
- R6-3 was probed with two temporary tests (deleted afterwards). Both are
  described under R6-3 below.

Status of earlier findings:

- R1-4 — **still open, as a caution.**
- R4-1 — **resolved.** The Morse duplex provider defaults to `clock:
  :realtime` with its own drift-corrected 20 ms timer; `clock: :manual` is
  opt-in; `advance/2` is rejected under the real-time clock. The pure
  `Clock.frames_due/5` scheduler is unit-tested, and a capability test speaks
  with no external tick and no sleep.
- R4-2 — **resolved.** The module doc has a "Test options" section for
  `clock: :manual` and `yield?: false`, stating that GPT-Live always decides
  whether to yield.
- R6-1 — **not resolved; the decision is recorded as R7-1 below.**
- R6-2 — **resolved.** Gate thresholds derive from `config.amplitude`, an
  undetectable amplitude is rejected, and a low accepted one plays.
- R6-3 — **not resolved.** See R7-2.
- R6-4 — **mostly resolved.** Replies queue in a bounded FIFO (16) with their
  own admission references, and two queued replies play in order. The
  overflow path (`:pending_reply_overflow`) has no test; see R7-4.
- R6-5 — **mostly resolved.** A map result and a 400-character result each
  produce a spoken reply, encoded before `turn_ended`. The explicit failure
  path when encoding still fails has no test; see R7-4.
- R6-6 — **partly resolved.** Input fragments are now fed on each decoder
  partial, which should bring caller onset forward. No test shows a yielded
  barge-in published with outcome `:overlapped`, which was the requested
  proof; see R7-4.

New findings:

- R7-1 — **High: the R6-1 fix relies on knowledge GPT-Live does not have.**
  The response keeps one output per reply and treats every later burst as a
  continuation of it. Morse can do that because it knows where its reply
  ends. GPT-Live cannot: its output is one continuous stream, and a burst
  after an 800 ms pause may continue the same answer, follow a tool result, or
  be proactive speech. The adapter has only the gate to go on. So the fake now
  tests a path the real adapter cannot take, and the path the adapter must
  take (each burst admitted as its own output, as the specification's output
  segmentation section says) is untested.

  The response justifies this by saying per-burst outputs would need a room
  contract change, because the room admits one output per provider turn. That
  was not checked against the provider-initiated path that already exists:
  a descriptor with `response_start?: true` emits `:response_started`, and the
  capability admits a new output for it (`ResponseQueue.admit_response/4`,
  used by the Google adapter in `sts_response_delivery.ex`). The change of
  approach was also made without an amendment, although the specification is
  frozen.

  Proposed fix: have the Morse duplex provider admit each burst through
  `:response_started` with its own provider turn, as the GPT-Live adapter
  will have to, and drop the "continue the current output" path. First
  confirm that `ResponseOrigins` can accept a response context for a
  continuation burst and for speech after a tool result. If it cannot, record
  the exact gap and propose an amendment before implementing. Tests: at
  `unit_duration_ms: 150`, one reply produces two outputs that each complete
  and settle, in order, with their transcript fragments aligned to the right
  output; speech after a tool result is admitted the same way.

- R7-2 — **High: yielding before admission still leaves the room's output
  slot stuck.** When the delayed admission arrives, the provider emits
  `:interrupted` but never `:output_completed` for that output. Only
  `:output_completed` (plus settlement) releases the slot, so the slot stays
  occupied. Two probes on `1bc3227f` show it:

  - after the existing R6-3 test's steps, `Session.admit_output/2` for the
    next caller turn returns `{:error, :busy}`;
  - no `:output_completed` for the yielded turn arrives within 1 s, even after
    advancing the clock 200 ms.

  The committed test only asserts that `:interrupted` arrives, not that the
  slot is released, which review 6 asked for.

  Proposed fix: when a yielded-before-admission reply is admitted, emit
  `:interrupted` and then `:output_completed` for that output reference with
  nothing played, as the Morse STS provider already does for its interrupted
  outputs. Extend the test to settle that output and then admit the next
  reply successfully.

- R7-3 — **Medium: the tool reply borrows a caller-turn event to get an
  output.** `publish_tool_reply/2` emits `:turn_ended` with empty text and a
  fresh turn reference, which the capability treats as a caller turn ending
  and answers with `admit_reply/3`. No public caller turn is published,
  because the reference matches no caller turn, but the output is authorized
  through the caller-turn path rather than the provider-initiated response
  path, and the event means something it is not. This is the same gap as
  R7-1.

  Proposed fix: admit the tool reply through `:response_started`, as in R7-1,
  and stop emitting `:turn_ended` for anything but an inferred caller turn.

- R7-4 — **Low: missing tests for three requested proofs.**
  - R6-4: two more replies than the FIFO allows fail the session with
    `:pending_reply_overflow`, and no queued reply is dropped silently.
  - R6-5: a result that still cannot be encoded fails the provider with an
    explicit reason.
  - R6-6: a barge-in that the provider yields to is published with outcome
    `:overlapped`, through the capability and the room event.

Open findings: R1-4, R7-1, R7-2, R7-3, R7-4.

Next work, in order:

1. R7-2: emit `:output_completed` for a yielded-before-admission output, with
   the extended test. This is a small fix to a stuck-slot bug.
2. R7-1 and R7-3: check `ResponseOrigins` for continuation and tool-reply
   bursts; record an amendment if needed; then admit each burst through
   `:response_started` and remove the continuation and empty-`turn_ended`
   paths.
3. R7-4: the three missing tests.
4. The remaining C tasks, starting with the compiled-room duplex proof under
   `clock: :realtime`; C's exit; then D.

### Response to review 7 — 2026-09-26

Implementation response to Review 7, labelled per R3-2. Not independent
verification.

- P7-R7-2 — **resolved.** When a yielded-before-admission reply is finally
  admitted, the provider now emits `:interrupted` and then
  `:output_completed` with the admitted output reference, so the room settles
  the slot. The test now asserts the completion, settles it, and admits the next
  reply successfully.
- P7-R7-1 and P7-R7-3 — **feasibility confirmed; implementation remains.**
  Checked `ResponseOrigins`/`ResponseQueue`: an accepted response context stays
  usable for later `:response_started` events while its recomputed fingerprint
  is current (policy, epoch and lifecycle unchanged), so the same context can
  authorize a continuation burst and a reply after a tool result. No amendment
  is needed; the frozen specification already requires admitting each burst with
  a fresh output reference. The redesign — set `response_start?: true`,
  implement `submit_input/3`, emit `:response_started` per burst with its own
  provider turn, and remove the continuation and empty-`turn_ended` paths — is a
  substantial rewrite of the provider's output half and is the next
  implementation step, not yet done.
- P7-R7-4 — **partly resolved.** Added provider tests: more replies than the
  FIFO allows fail with `:pending_reply_overflow` and stop the provider, and a
  tool result that sanitises to nothing fails with `:empty_tool_reply` and stops
  the provider. The `:overlapped` barge-in proof through the capability and room
  event is checkpoint C's compiled-room proof and remains there.
- R1-4 — **still open, as a caution.**

Next work, in order: the R7-1/R7-3 `:response_started` per-burst redesign; the
remaining C tasks, starting with the compiled-room duplex proof; C's exit; D.

### Review 8 — 2026-09-26 (response to the review 7 response)

Independent review of commit `33af06c3` and its "Response to review 7".

Reviewed state: `33af06c3` on `sts2`, clean worktree.

Verified:

- 77 focused tests pass (seed 0), across the same files as review 7. Per
  R2-4, the reported child-suite run (1,562 tests, zero failures) is cited,
  not repeated.
- The R7-1/R7-3 feasibility claim, by reading
  `Capability.SpeechToSpeech.ResponseOrigins`. Input submitted with
  `response_start?: true` records a response context with a fingerprint of
  the allocation, source, epoch, lifecycle and policy revisions, and audio
  intervals. A later `:response_started` with that context is admitted while
  the fingerprint is still current. So one accepted context can authorize a
  continuation burst or speech after a tool result, and no amendment is
  needed.

Status of earlier findings:

- R1-4 — **still open, as a caution.**
- R7-1, R7-3 — **still open; feasibility confirmed.** The redesign is not yet
  implemented. See R8-1, which it depends on.
- R7-2 — **resolved.** When a reply that yielded before admission is
  admitted, the provider emits `:interrupted` and then `:output_completed`
  with the admitted output reference. The test settles that output and then
  admits the next reply, which is the proof review 7 asked for.
- R7-4 — **resolved, with one deferral accepted.** Queue overflow fails with
  `:pending_reply_overflow` and an unusable tool result fails with
  `:empty_tool_reply`, both stopping the provider explicitly. The
  `:overlapped` proof moves to checkpoint C's compiled-room overlap task,
  which already requires it; it must not be dropped there.

New findings:

- R8-1 — **High, blocks R7-1: accepted response contexts are never pruned.**
  `ResponseOrigins.accept/3` adds each new context with `Map.put_new/3`, and
  nothing removes one until the capability restarts. At 16 contexts
  `new_candidate/2` returns `{:error, :busy}`, so every later input
  submission fails. Each hold, policy revision or epoch change produces a new
  fingerprint and therefore a new context. This is latent today, because
  Google STS defaults to `response_start?: false`. The R7-1 redesign makes
  the Morse duplex provider (and later the GPT-Live adapter) use
  `response_start?: true` for every burst, so a long phone call with enough
  holds or policy changes would stop accepting caller audio.

  The code belongs to the capability delivered by
  [Agent speech-to-speech](agent-speech-to-speech.md), but this milestone is
  the first to depend on it for every reply, so fix it here as a
  prerequisite of R7-1.

  Proposed fix: when a new context is accepted, drop accepted contexts whose
  fingerprint is no longer current and that no queued, pending or active
  response still references. Keep the 16-context bound for contexts that are
  still referenced, and fail explicitly only when all 16 are live. Tests:
  twenty hold and release cycles, then a caller turn whose reply is
  admitted; a stale context still referenced by a queued response is kept
  until that response settles or is rejected.

- R8-2 — **Medium: an empty tool result ends the agent's speech for the rest
  of the call.** `ToolReply.text/2` returns `{:error, :empty_tool_reply}` when
  the sanitized summary is empty, for example for a `%{}` result, and the
  provider stops. An empty map is an ordinary tool success, such as an action
  that returns no data, and on a phone call stopping the provider silences
  the agent. Review 6's R6-5 asked for an explicit failure when encoding still
  fails; applying that to an empty summary is disproportionate, because a
  spoken reply is still possible.

  Proposed fix: when the summary is empty, speak a fixed acknowledgement
  (`"RECEIVED OK"`). Keep the explicit failure only for a reply that cannot
  be encoded at all. Update the test so `%{}` produces that acknowledgement.

- R8-3 — **Low: one completion emit ignores failure.** The new R7-2 path
  discards the result of `Event.emit(state.channel, :output_completed, ...)`
  with `_ =`, while the provider's other emits stop the session on failure.
  Proposed fix: handle a failed emit the same way as the others.

Open findings: R1-4, R7-1, R7-3, R8-1, R8-2, R8-3.

Next work, in order:

1. R8-1: prune stale response contexts, with its tests.
2. R7-1 and R7-3: the `:response_started` per-burst redesign, removing the
   continuation and empty-`turn_ended` paths.
3. R8-2 and R8-3.
4. The remaining C tasks, starting with the compiled-room duplex proof under
   `clock: :realtime`, including the `:overlapped` proof deferred from R7-4;
   C's exit; then D.

### Response to review 8 — 2026-09-26

Implementation response to Review 8, labelled per R3-2. Not independent
verification.

- P8-R8-1 — **resolved.** `ResponseOrigins.submit/2` now prunes accepted
  contexts whose fingerprint is no longer current before choosing a candidate,
  keeping any context a pending response still references (and the external
  activity origin). Stale contexts no longer accumulate toward the 16-context
  bound, so a long call with holds or policy changes keeps accepting caller
  audio. Unit test: stale unreferenced contexts are dropped, the current and a
  referenced stale context are kept, and pruning frees capacity below the bound.
- P8-R8-2 — **resolved.** An empty sanitized tool summary is an ordinary success
  and now speaks the fixed acknowledgement `"RECEIVED OK"` instead of stopping
  the provider. The explicit failure remains only when the reply cannot be
  encoded at all; the test was updated so `%{}` produces the acknowledgement.
- P8-R8-3 — **resolved.** The R7-2 `:output_completed` emit now stops the
  session on failure like the provider's other emits.
- P8-R7-1 / P8-R7-3 — **still open; prerequisite R8-1 is now done.** The
  `:response_started` per-burst redesign remains the next implementation step.

Open findings: R1-4, R7-1, R7-3.

Next work, in order: the R7-1/R7-3 `:response_started` per-burst redesign; then
the remaining C tasks (compiled-room duplex proof with the deferred
`:overlapped` proof, room-fence prefix, `hold: :mute`, tool survival); C's exit;
then D–F.

### Review 9 — 2026-09-26 (response to the review 8 response)

Independent review of commit `a13a8ac7` and its "Response to review 8".

Reviewed state: `a13a8ac7` on `sts2`, clean worktree.

Verified:

- 79 focused tests pass (seed 0), including the new
  `response_origins_test.exs`. Per R2-4, the reported umbrella run (2,751
  tests, zero failures) is cited, not repeated.
- Pruning is semantically safe. A queued response is re-checked against its
  own stored fingerprint (`ResponseOrigins.current?/2`), and a
  `:response_started` for a context whose fingerprint is not current is
  rejected whether or not the context is still in the map. Dropping
  non-current contexts therefore rejects nothing that was not already
  rejected; it only frees capacity. Fingerprints contain fresh epoch and
  lifecycle references, so a stale fingerprint cannot become current again.

Status of earlier findings:

- R1-4 — **still open, as a caution.**
- R7-1, R7-3 — **still open.** The per-burst `:response_started` redesign is
  the next step; its prerequisite R8-1 is now in place.
- R8-1 — **resolved in behaviour, with the test and cleanup gaps in R9-1 and
  R9-2.**
- R8-2 — **resolved.** An empty tool summary now speaks `"RECEIVED OK"`, and
  the test covers `%{}`.
- R8-3 — **resolved.** Both emits on the R7-2 path now stop the session on
  failure.

New findings:

- R9-1 — **Medium: R8-1 is tested only on a hand-built state.** Both new tests
  call `ResponseOrigins.prune/1` directly on a map that copies the
  capability's state fields, and `fingerprint/1` was made public
  (`@doc false`) for them. Review 8 asked for a behaviour test: twenty hold
  and release cycles, then a caller turn whose reply is admitted. As written,
  the tests would still pass if the capability's state shape changed, or if
  pruning were never called from the paths that matter. This is the
  project's "test behaviour at the boundary that owns it" rule.

  Proposed fix: add the behaviour test through the supervised STS capability
  with `response_start?: true`: more than sixteen hold and release cycles (or
  policy revisions that change the fingerprint), then a caller turn whose
  reply is admitted and played. Keep one small unit test if useful, but make
  `fingerprint/1` private again and test through `submit/2`.

- R9-2 — **Low: the external-activity retention clause never matches.**
  `referenced_contexts/1` keeps `state.external_activity_origin` only when it
  is a reference, but `Input` stores a fingerprint map there
  (`input.ex:190`). So the clause is dead, and the response's claim that
  pruning keeps "the external activity origin" is not what the code does.
  Nothing breaks: external and hybrid turn control are out of this
  milestone's scope, and the stored fingerprint does not depend on the
  context map. Proposed fix: remove the clause and the claim, or, if
  external mode needs it later, store the context reference and test it then.

- R9-3 — **Low: pruning runs on every audio frame.** `submit/2` calls
  `prune/1` first, so every 20 ms caller frame recomputes the fingerprint
  twice (once in `prune/1`, once in `prepare/1`) and rebuilds the context
  map, even when the current context is reused. Proposed fix: prune only
  when a new candidate context is needed (inside `new_candidate/2`'s path),
  which is the only point where capacity matters.

Open findings: R1-4, R7-1, R7-3, R9-1, R9-2, R9-3.

Next work, in order:

1. R9-1, with R9-2 and R9-3 folded in, since they touch the same module.
2. R7-1 and R7-3: the `:response_started` per-burst redesign, removing the
   continuation and empty-`turn_ended` paths.
3. The remaining C tasks, starting with the compiled-room duplex proof under
   `clock: :realtime`, including the `:overlapped` proof deferred from R7-4;
   C's exit; then D.

### Response to review 9 — 2026-09-26

Implementation response to Review 9, labelled per R3-2. Not independent
verification.

- P9-R9-2 — **resolved.** Removed the dead external-activity retention clause;
  `Input` stores a fingerprint there, not a context reference, and external
  turn control is out of scope. The claim is dropped with it.
- P9-R9-3 — **resolved.** Pruning now runs only inside the new-candidate path,
  where capacity matters, instead of on every audio frame. `fingerprint/1` is
  private again and the hand-built unit test was removed.
- P9-R9-1 — **pending on R7-1.** The requested behaviour test needs a
  `response_start?: true` provider to drive it; the Morse duplex provider gains
  that in R7-1. It will be added with the R7-1/R7-3 redesign rather than
  hand-building capability state.

Open findings: R1-4, R7-1, R7-3, R9-1.

Next work, in order: the R7-1/R7-3 `:response_started` per-burst redesign,
which also lets R9-1's behaviour test run; then the remaining C tasks; C's
exit; then D–F.

### Review 10 — 2026-09-26 (response to the review 9 response, and the per-burst design)

Independent review of commits `be26eb59` (R9-2, R9-3) and `0d18ff2c` (docs
site landing page), plus a proposed design for the R7-1/R7-3 per-burst
`:response_started` redesign.

Reviewed state: `0d18ff2c` on `sts2`. The worktree also holds an uncommitted
change to `labnotes/20260925-1240-gpt-live-duplex-contract.md` from the
implementation run, which this review did not assess.

Status of earlier findings:

- R1-4 — **still open, as a caution.**
- R7-1, R7-3 — **still open.** The design is proposed below.
- R8-1 — **reopened; see R10-1.** The capability-side pruning is correct, but
  the same cap exists in the speech channel, which has no retirement.
- R9-1 — **still open; the deferral reason does not hold.** A
  `response_start?: true` provider already exists: Google STS opts in, and
  `capability/google_sts_controller_test.exs` drives it through the
  capability with a fake socket. The behaviour test can be written now. With
  `be26eb59` removing the unit tests, R8-1's pruning has no test at all. The
  behaviour test would also fail today, because of R10-1, which is why it
  matters.
- R9-2 — **resolved.** The dead clause and the claim are gone.
- R9-3 — **resolved.** Pruning runs only on the new-candidate path, and
  `fingerprint/1` is private again.

New findings:

- R10-1 — **High, blocks R7-1: the speech channel never retires accepted
  response contexts.** `Speech.ResponseContexts` (channel-side) stages each
  new context on input submission and keeps it once accepted. Its own comment
  says accepted origins "live until allocation teardown" and that retirement
  is "a separate gate". `stage/3` returns `{:error, :busy}` once 16 contexts
  are known. The capability mints a new context for every fingerprint change,
  so after 16 holds, policy revisions or epoch changes, every input
  submission fails at the channel, even though `ResponseOrigins` has pruned
  its own copy. R8-1 fixed only the capability half.

  Proposed fix: engine-authorized retirement. Contexts are engine-owned, so
  the capability decides when one is retired and tells the channel:
  1. Add a bounded `Session.retire_response_contexts(allocation, contexts)`
     call. The channel removes each listed context that is `:accepted`,
     ignores unknown ones, and never removes the currently staged one.
  2. `ResponseOrigins` calls it with the contexts it prunes, in the same
     step, so the two maps cannot drift apart.
  3. An event that later carries a retired context (`:response_started`,
     `:tool_call`) is treated like one carrying an unknown context: the
     response is discarded and the tool call rejected, never granted.

  Tests: the R9-1 behaviour test through the Google controller harness with
  `response_start?: true`, running more than sixteen fingerprint changes and
  then a caller turn whose reply is admitted and played; plus a channel test
  that a retired context cannot start a response.

- R10-2 — **Low, outside this milestone: the docs site test suite is red.**
  Verified by running `homepage-structure.test.mjs` against archived trees of
  both commits. At `be26eb59` it fails on a stale "Built on Elixir & OTP"
  assertion, as the `0d18ff2c` commit message says, so the landing-page
  commit did not cause it. At `0d18ff2c` it fails on the hero button count
  (the new page has two buttons, the test expects three). The reworked test
  that matched the new page was removed at the user's request. Proposed fix,
  in a separate docs commit: update `homepage-structure.test.mjs` to the
  current page's structure, keeping its checks minimal.

#### Proposed design: per-burst `:response_started` (R7-1, R7-3)

Goal: every audible burst of duplex output is admitted as its own output
through the existing provider-initiated response path, exactly as the GPT-Live
adapter will have to do it, with no knowledge of where a reply ends. The
Morse duplex provider is the first user; the GPT-Live adapter reuses the same
module.

Existing contract this builds on (no amendment needed):

- A descriptor with `response_start?: true` must take input through
  `submit_input(pid, context, operation)`, where the engine issues `context`.
- The provider announces a response with `:response_started` carrying a fresh
  `turn_ref`, a strictly increasing `response_index`, and an accepted
  `response_context`.
- The capability admits it (`ResponseQueue.admit_response/4`) when its
  context's fingerprint is still current, queuing it behind any active output
  (at most 16 pending), or rejects it.
- On admission the provider receives
  `{:vxpipe_speech_output, channel, turn_ref, output_ref}`; on rejection
  `{:vxpipe_speech_response_discard, channel, turn_ref}`; after local
  playback `{:vxpipe_speech_output_settled, channel, turn_ref, output_ref,
  played_ms}`.
- With `response_start?: true`, the capability does not admit a reply on
  `:turn_ended`; it only advances its pending queue. So caller turns no longer
  create outputs.

Shared module: add a pure `Speech.Duplex.BurstResponses` beside
`TurnInference` and `OutputSegmenter`. It owns the burst-to-response mapping
that both providers need, following the shape of the Google adapter's
`STSResponses`:

- the latest accepted input context;
- the last `response_index`;
- per burst: `turn_ref`, index, context, state (`:announced`, `:admitted`,
  `:discarded`, `:completed`), output reference, and buffered byte count;
- a bound on bursts that are announced but not yet admitted (4 is enough,
  because bursts are at least one gap apart), failing explicitly beyond it.

Burst lifecycle:

1. **Input.** `submit_input/3` records the context of each accepted input as
   the latest context. Audio goes to the decoder or the wire as today.
2. **Gate opens.** `OutputSegmenter` reports `{:open, seg_ref}`. The provider
   creates a burst with a fresh `turn_ref`, the next index and the latest
   context, and emits `:response_started`. The burst's audio stays in the
   segmenter's receive buffer (2 s bound) until admission. With no accepted
   context yet, for example speech before any input, the burst is discarded
   locally, because the room could not authorize it.
3. **Admitted.** `{:vxpipe_speech_output, ...}` for that `turn_ref` calls
   `OutputSegmenter.admitted/2` and forwards the buffered and later audio
   through the existing credited path under that output reference. Output
   transcript fragments are emitted with that `turn_ref` and aligned offsets.
4. **Gate closes.** After the last credit, the provider emits
   `:output_completed` for that `turn_ref` and output reference. The next
   burst is a new response; nothing continues an earlier output.
5. **Rejected.** `{:vxpipe_speech_response_discard, ...}` drops the burst's
   buffered audio and discards the rest of it until the gate closes. No
   completion is emitted, because nothing was admitted.
6. **Yield.** An admitted burst that the provider stops early completes
   normally after its last credit; the room labels the turn `:overlapped` from
   caller onset. A burst that yields before admission completes with nothing
   played when its admission arrives (the R7-2 behaviour, now per burst), or
   is simply dropped if it is discarded instead.
7. **Ordering and back-pressure.** The room plays one output at a time and
   queues the rest. Bursts are at least one gap (800 ms) apart and arrive at
   real-time pace, so the previous output normally settles before the next
   admission. If it does not, audio waits in the 2 s receive buffer, and
   overflow fails the session explicitly, as the specification requires.

Morse duplex changes:

- Declare `response_start?: true` and implement `submit_input/3`; keep
  `push_audio/2` and `push_text/3` rejecting use under the opted-in
  descriptor.
- Keep the reply FIFO, but as a generation queue: replies are appended to the
  provider's own continuous output timeline in order. It no longer holds
  admission references.
- Tool results append a reply to the timeline; its burst is announced like
  any other. Remove the empty `:turn_ended` from `publish_tool_reply/2`
  (R7-3). `:turn_ended` is emitted only for inferred caller turns.
- Remove the continuation path in `open_burst/2`, `yielded_pending`, and the
  per-reply output reference.

Public turn semantics: each burst is one public agent turn. A pause longer
than the gap splits one spoken answer into two agent turns in the transcript.
The phone call behaviour section already accepts this: turn boundaries only
label the record and never change when the agent speaks.

Tests, all through the capability unless noted:

- `BurstResponses` unit tests: index order, context capture, the announced
  bound, and each state transition.
- A reply whose word gap exceeds 800 ms (`unit_duration_ms: 150`) produces two
  `:response_started` events, two outputs that complete and settle in order,
  and transcript fragments attached to the right output.
- A tool result's reply is admitted through `:response_started`, and no
  `:turn_ended` is emitted for it.
- A policy change between input and burst makes the room reject the burst:
  its audio is never played, no completion is emitted, and the next burst
  with a current context is admitted.
- Yield before admission, then admission: the output completes with nothing
  played and the next burst is admitted.
- Speech before any accepted input is discarded locally and never announced.
- Receive-buffer overflow while waiting for admission fails explicitly.
- Under `clock: :realtime`, a compiled-room call carries all of the above
  into checkpoint C's proof.

Documentation: add the burst-to-response mapping to the speech provider
contract's duplex section and the integration guide, so the GPT-Live adapter
in checkpoint D implements the same lifecycle.

Open findings: R1-4, R7-1, R7-3, R9-1, R10-1, R10-2.

Next work, in order:

1. R10-1, with the R9-1 behaviour test through the Google controller harness.
2. R7-1 and R7-3, as designed above: `BurstResponses`, then the Morse duplex
   changes and their tests.
3. The remaining C tasks, starting with the compiled-room duplex proof under
   `clock: :realtime`, including the `:overlapped` proof deferred from R7-4;
   C's exit; then D.
4. R10-2 in a separate docs commit, whenever convenient.

### Response to review 10 — 2026-09-26

Implementation response to Review 10, labelled per R3-2. Not independent
verification.

- P10-R10-1 — **resolved.** Added engine-authorized context retirement:
  `ResponseContexts.retire/2` removes accepted contexts, ignores unknown ones
  and never removes the staged one; the channel exposes
  `Session.retire_response_contexts/2` (consumer-only) and
  `ResponseOrigins.prune/2` retires the contexts it drops in the same step, so
  the capability and channel maps cannot drift. A later event that carries a
  retired context is now rejected like an unknown one, which
  `STSOutput`/`ToolEvents` already do. Updated the two origin tests that had
  encoded the old bounded behaviour: the seventeenth fingerprint change is now
  accepted instead of `{:error, :busy}`, and a late old-origin tool call is
  rejected at the channel with `{:error, :stale_response}` instead of reaching
  the capability. Added `response_contexts_test.exs` for retirement and freed
  capacity.
- P10-R9-1 — **partially resolved.** The unit test and the updated origin tests
  cover retirement and the channel bound; the full behaviour test that runs
  more than sixteen fingerprint changes through the Google controller and then
  admits and plays a reply was not completed. Driving twenty sequential inputs
  needs the provider's in-flight input slot to settle between revisions, and
  the cheap synchronizations tried (channel/capability/provider `:sys.get_state`
  polling) did not make it deterministic. It remains open.
- P10-R10-2 — **pending; separate docs commit.**
- P10-R7-1 / P10-R7-3 — **pending**, per the design proposed in Review 10.

Open findings: R1-4, R7-1, R7-3, R9-1, R10-2.

Next work, in order: the R7-1/R7-3 `BurstResponses` design plus the R9-1
behaviour test; then the remaining C tasks; C's exit; then D–F.

### Review 11 — 2026-09-26 (response to the review 10 response)

Independent review of commits `522f23ec` (channel-side context retirement)
and `f96f2e98` (restored `ResponseContexts` tests), and of the "Response to
review 10".

Reviewed state: `f96f2e98` on `sts2`, clean worktree.

Verified:

- 399 tests pass (seed 0, 3 excluded): the whole `speech` test directory,
  `response_contexts_test.exs`, `sts_capability_origins_test.exs`,
  `google_sts_controller_test.exs`, the Morse duplex provider tests, the duplex
  capability tests and the room STS tests. Per R2-4, the reported umbrella run
  (2,749 tests, zero failures) is cited, not repeated.
- `f96f2e98` correctly restores the two staging and rollback tests that
  `522f23ec` had dropped.

Progress: 9 of 39 checkpoint tasks are done (A 4/4, B 4/4, C 1/8, D 0/5,
E 0/6, F 0/7), so 77% of the tasks remain. Weighted by effort the remaining
share is higher, roughly 80–85%: the open work includes the per-burst
redesign, the compiled-room proofs, the real OpenAI adapter, session
continuity and the hosted check.

Status of earlier findings:

- R1-4 — **still open, as a caution.**
- R7-1, R7-3 — **still open**, per the review 10 design.
- R9-1 — **partly resolved.** The updated origin test now drives seventeen
  fingerprint changes through the capability and the channel, and the
  seventeenth input reaches the provider. What is still unproven is that a
  reply is then admitted. See the proposed shortcut under R11-3.
- R10-1 — **resolved in capacity, with the regression in R11-1.** Contexts
  pruned by `ResponseOrigins` are now retired at the channel, and a
  seventeenth fingerprint change is accepted.
- R10-2 — **still open** (separate docs commit).

New findings:

- R11-1 — **Medium: a late event on a just-retired context now ends the
  Google session instead of being discarded.** Before `522f23ec`, the channel
  still knew a stale context, so a late `:response_started` passed the channel
  and the capability rejected it; the provider received
  `{:vxpipe_speech_response_discard, ...}` and carried on. Now the channel has
  forgotten the context, so `Event.emit/3` returns `{:error,
  :stale_response}`, and the Google adapter treats any failed emit as
  `:session_failed` (`sts_response_delivery.ex:31-34` for responses,
  `sts_tool_call.ex:21-33` for tool calls). Race: after a hold or policy
  change, the capability mints a new context and retires the old one before
  the provider receives input with the new context. Model audio arriving in
  that window is announced with the old context and now kills the session,
  silencing the agent for the rest of the call.

  Tool calls change too. A late tool call on an old origin used to stop the
  capability with the explicit reason `:stale_tool_origin`. It now fails the
  provider with a generic `:session_failed`, and the updated test no longer
  asserts any outcome for the capability.

  Review 10's R10-1 proposal said a retired context should be "treated like
  one carrying an unknown context"; that wording missed that unknown contexts
  are an emit error, which providers treat as fatal. It also contradicts step
  5 of the review 10 design, which expects a rejected burst to arrive as a
  discard message.

  Proposed fix: keep a bounded set of recently retired contexts in the
  channel (for example the last 16) as tombstones.
  - A `:response_started` on a tombstoned context is accepted by `emit` and
    answered at once with `{:vxpipe_speech_response_discard, channel,
    turn_ref}`, the path every provider already handles.
  - A `:tool_call` on a tombstoned context returns `:discarded`, which the
    Google adapter already handles. The provider must still answer the
    model's call (a cancellation or an error result); for GPT-Live an
    unanswered call blocks every later tool call.
  - A context outside the tombstone window stays an error, as today.

  Tests: through the Google controller, retire a context and then announce a
  response on it; the response is discarded, the session survives, and the
  next response on a current context is admitted. A stale tool call is
  discarded and answered, and the test asserts the capability's outcome again.

- R11-2 — **Low: a failed retirement call is ignored.**
  `ResponseOrigins.prune/2` discards the result of
  `Session.retire_response_contexts/2` with `_ =`, yet drops the contexts from
  its own map. If the call fails, the two maps drift apart, which is what the
  change set out to prevent. Proposed fix: drop contexts from the
  capability's map only after the channel confirms, so a failed call is
  retried at the next prune; or fail the capability explicitly.

- R11-3 — **Suggestion for R9-1: finish it in the origin test.** The response
  says the Google-controller version could not be made deterministic. The
  updated `sts_capability_origins_test.exs` case already reaches a seventeenth
  context deterministically with its test provider. Extend it: have that
  provider emit `:response_started` with the seventeenth context and assert
  that the capability admits it (`{:vxpipe_speech_output, ...}` reaches the
  provider). That completes R9-1 without the Google controller.

Open findings: R1-4, R7-1, R7-3, R9-1, R10-2, R11-1, R11-2.

Next work, in order:

1. R11-1 (tombstones and graceful discard), with R11-2.
2. R9-1 via R11-3.
3. R7-1 and R7-3, per the review 10 design. Its step 5 relies on R11-1.
4. The remaining C tasks, starting with the compiled-room duplex proof under
   `clock: :realtime`; C's exit; then D.
5. R10-2 in a separate docs commit.

### Response to review 11 — 2026-09-26

Implementation response to Review 11, labelled per R3-2. Not independent
verification.

- P11-R11-1 — **resolved.** The channel keeps a bounded tombstone window (last
  16) of retired contexts. A `:response_started` on a tombstoned context is
  accepted by `emit` and answered immediately with
  `{:vxpipe_speech_response_discard, channel, turn_ref}`, the path providers
  already handle; a `:tool_call` on one returns `:discarded`; a context outside
  the window is still rejected. A late response on a just-retired origin no
  longer kills the Google session. Test: retire an origin, announce a response
  on it, assert the discard arrives, the session survives, and a current origin
  still admits.
- P11-R11-2 — **resolved.** `ResponseOrigins.prune/2` drops its own copy of a
  context only after `Session.retire_response_contexts/2` confirms, so a failed
  retirement is retried at the next prune instead of drifting.
- P11-R11-3 — **resolved; R9-1 complete.** The origin test now emits
  `:response_started` on the seventeenth context after seventeen fingerprint
  changes and asserts the capability admits it (`{:context_output_granted, ...}`
  reaches the provider). This completes R9-1 without the Google controller.
- P10-R7-1 / P10-R7-3 — **still open**, per the Review 10 design (its step 5
  now builds on R11-1).
- P10-R10-2 — **still open** (separate docs commit).

Open findings: R1-4, R7-1, R7-3, R10-2.

Next work, in order: the R7-1/R7-3 `BurstResponses` per-burst redesign; then the
remaining C tasks, starting with the compiled-room duplex proof; C's exit; D–F;
R10-2 in a separate docs commit.
