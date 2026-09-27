# GPT-Live completion plan

Status: build plan written 2026-09-26 by the milestone's independent reviewer
(review 12). It turns every open task in
[GPT-Live speech-to-speech](milestones/gpt-live-speech-to-speech.md) into ordered
work packages with specifications, module architecture, tests and acceptance.
The milestone stays the source of truth for scope and the frozen
specification; this plan says how to build what remains. Where a package
needs a contract change, it says so and names the amendment to record.

## How to use this plan

- Work the packages in order. Each package is one coherent commit (two where
  noted), leaves the umbrella green, and closes the milestone checkboxes it
  names.
- Follow the project rules in `AGENTS.md`: red-green for every behaviour
  change, focused tests while iterating, all five root gates before each
  commit, no `Process.sleep/1` in tests, `start_supervised!/1` for processes.
- After each package, append a "Response to review N" section to the
  milestone (never edit a review), tick only the boxes whose acceptance passed,
  and update `labnotes/20260925-1240-gpt-live-duplex-contract.md`.
- Start a fresh implementation session for each package or two. Each package
  below is written to be understood without the conversation history.
- Stop only for the checkpoint F hosted check (it needs explicit billable
  authorization) or for a blocker you record in the milestone with evidence.

## Where things stand

Current snapshot (2026-09-27): checkpoints A–D are locally complete. E covers
history reseeding, all three post-reseed speech cases, pending host tool
results across a lost GPT-Live session, and provider-originated transfer
through compiled Morse and fake GPT-Live rooms. Both providers now reach the
room-owned transfer binding; destination commit tears down the source and
failure returns a tool result while keeping the same session usable. Package
8 was split into reviewable checkpoints while retaining the plan's order.
F has Console enablement, documentation, rendered setup inspection, the
ten-call local duplex load lane, and a reviewed opt-in hosted harness
(`a2946557`). The Package 9 review found that E history was appended before
the room accepted text. The room now acknowledges router-approved caller
text and delivered agent text before the capability records history. The
red-green boundary tests and all local root gates passed in checkpoint 8's
publication correction. A follow-up room-ordered barrier now waits for queued
and in-progress publications before either local provider snapshots history;
its final root verification is recorded in the milestone (2,868 tests, zero
failures). The authorized hosted service and phone check remains open. Package
10's docs-site test was committed separately as `97e5c0af` and its eight-test
lane passes. The milestone checklist is at 33 of 34 tasks (97.1%) and remains
the source of truth for acceptance.

Plan audit (2026-09-27): the implementation follows the package order. Package
8 was split into coherent commits, and the publication barrier closes the
strict snapshot rule in checkpoint E. OpenAI's LLM and GPT-Live setup was
enabled before the hosted check at the user's explicit direction. Package 10
remains a separate docs-site commit. The only outstanding acceptance is the
authorized hosted service and phone check in Package 9.

Original planning snapshot (before implementation):

Checkpoints A and B are done (8 of 8 tasks). Checkpoint C has 1 of 8 tasks
done; D, E and F have none. The capability-side and channel-side response
context retirement (R8-1, R10-1, R11-1, R11-2) and its behaviour test (R9-1)
are implemented; at the time of writing that last step was uncommitted.

Existing pieces you will reuse:

| Piece | Location | What it gives you |
| --- | --- | --- |
| Duplex descriptor facts | `speech/descriptor.ex` | `output_shape`, `barge_in`, `continuity`, `tool_cancellation?`, `hold`, `:inferred_gap` |
| Caller turn inference | `speech/duplex/turn_inference.ex` | fragment grouping, quiet-audio and timeline-gap turn ends |
| Output segmentation | `speech/duplex/output_segmenter.ex` | energy gate, 800 ms gap, 300 ms pre-roll, 2 s receive buffer, fragment alignment |
| Morse duplex provider | `provider/morse_code_duplex/` | local GPT-Live stand-in with real-time and manual clocks |
| Provider-initiated responses | `capability/speech_to_speech/response_queue.ex`, `response_origins.ex`, `speech/event_delivery.ex` | `:response_started` admission, rejection as `{:vxpipe_speech_response_discard, ...}` |
| Output protocol | `speech/sts_provider.ex` moduledoc | admission, credit, `:output_completed`, settlement message |
| Socket client | `speech/socket.ex` (behaviour), `providers/google/sts_socket.ex` (example) | supervised WebSocket with owner messages |
| Credential path | `plan_startup/speech_provider_resolution.ex` (`authenticate_speech/2`) | `api_key` credentials become the `:api_key` private option |
| Provider manifests | `apps/vxpipe_providers/lib/vxpipe/providers/` | `id/0`, `capabilities/0`, `Credential`, `CredentialValidation`, `Registry` |
| Compiled-room STS tests | `test/.../room_authority/sts_transcript_modes_test.exs`, `sts_call_test.exs` | real room calls with Morse STS |
| Load lane | `test/.../speech/call_load_test.exs`, `test/support/call_load/` | ten-call measured lane, tagged `:integration` |

Paths are relative to `apps/vxpipe_call_engine/lib/vxpipe/call_engine/` unless
they start with `apps/` or `test/`.

## Package order

| # | Package | Closes |
| --- | --- | --- |
| 0 | Commit the in-progress R11 work | R11-1, R11-2, R9-1 |
| 1 | Per-burst responses (`BurstResponses`) | R7-1, R7-3 |
| 2 | Select the Morse duplex provider from a call spec | prerequisite for 5 |
| 3 | Aligned spoken prefix | C "room fence publishes only the aligned prefix" |
| 4 | Hold by muting | C "hold with `hold: :mute`" |
| 5 | Compiled-room duplex proofs | C remaining tasks and C's exit |
| 6 | OpenAI provider package | D first task |
| 7 | GPT-Live adapter over a fake socket | D remaining tasks and D's exit |
| 8 | Session continuity and lifecycle | E, all tasks |
| 9 | Documentation, Console gating, load, review, hosted check | F, all tasks |
| 10 | Docs site homepage test | R10-2 (separate docs commit, any time) |

---

## Package 0 — commit the in-progress R11 work

The worktree holds the tombstone window for retired contexts (R11-1), the
confirmed-retirement change (R11-2) and the seventeenth-context admission test
(R9-1). Run the five root gates, then commit it with its milestone response
and labnote update. If the known load-sensitive `SpeechToTextTest` flake
appears, rerun that file in isolation and record both runs.

## Package 1 — per-burst responses (R7-1, R7-3)

Goal: every audible burst of duplex output is admitted as its own output
through `:response_started`, as the GPT-Live adapter must do, with no
knowledge of where a reply ends. The full lifecycle is in review 10
("Proposed design: per-burst `:response_started`"); this section fixes the
module interface.

### `Speech.Duplex.BurstResponses` (new, pure)

State: `latest_context`, `last_index`, `bursts` (map from `turn_ref`),
`order` (FIFO of `turn_ref`s), `maximum_unadmitted` (default 4).

Burst record: `%{turn_ref, index, context, seg_ref, state, output_ref,
yielded?}` where `state` is `:announced | :admitted | :discarded |
:completed`.

Functions (each returns `{burst_responses, actions}`, where actions are
tuples the provider executes in order):

- `new(options)`
- `input_accepted(br, context)`: records the latest context.
- `burst_opened(br, seg_ref)`: with no `latest_context`, returns
  `[{:drop_segment, seg_ref}]`. Otherwise mints `turn_ref`, increments the
  index and returns `[{:announce, turn_ref, index, context}]`. Beyond
  `maximum_unadmitted` announced bursts, returns `{:error,
  :pending_response_overflow}`.
- `admitted(br, turn_ref, output_ref)`: returns `[{:admit_segment, seg_ref,
  output_ref}]`, or `[{:complete_empty, turn_ref, output_ref}]` when the burst
  already yielded.
- `discarded(br, turn_ref)`: returns `[{:drop_segment, seg_ref}]` and marks
  the burst discarded.
- `burst_closed(br, seg_ref)`: returns `[{:complete, turn_ref, output_ref}]`
  when admitted; otherwise marks the burst closed and completes it on
  admission.
- `yielded(br)`: marks the newest open burst yielded.
- `turn_for_segment(br, seg_ref)`: for attaching transcript fragments.

The provider does the I/O: emit `:response_started`, call
`OutputSegmenter.admitted/2`, submit credited audio, emit
`:output_completed`. Keep all branching in the pure module so the GPT-Live
adapter reuses it unchanged.

### Morse duplex changes

1. Descriptor: `response_start?: true`. Implement `submit_input/3`; call
   `BurstResponses.input_accepted/2` for each accepted input. `push_audio/2`
   and `push_text/3` return `{:error, :unsupported_operation}`.
2. Replace the reply FIFO's admission references with a generation queue:
   replies (caller replies and tool replies) are appended to the provider's
   continuous output timeline in order.
3. Delete the continuation path in `open_burst/2`, `yielded_pending`, the
   per-reply output reference, and the empty `:turn_ended` in
   `publish_tool_reply/2`. Emit `:turn_ended` only for inferred caller turns.
4. Handle `{:vxpipe_speech_response_discard, channel, turn_ref}` through
   `BurstResponses.discarded/2`.

### Tests (red first)

`BurstResponses` unit tests for each function and state transition, and
through the capability:

- At `unit_duration_ms: 150`, one reply produces two `:response_started`
  events, two outputs that complete and settle in order, and fragments
  attached to the right output.
- A tool result's reply is admitted through `:response_started`; no
  `:turn_ended` is emitted for it.
- A policy change between input and burst: the burst is discarded, never
  played, no completion is emitted, and the next burst on a current context
  is admitted.
- Yield before admission, then admission: the output completes with nothing
  played and the next burst is admitted.
- Speech before any accepted input is dropped and never announced.
- More than four unadmitted bursts fail with `:pending_response_overflow`.

## Package 2 — select the Morse duplex provider from a call spec

Goal: a compiled room can run the Morse duplex provider from an ordinary call
spec.

- Selection: `speech_to_speech: %{provider: "morse", model: "morse-duplex",
  options: %{...}}`. The model name keeps one provider identity and one
  credential-free manifest entry.
- `CapabilityCatalog`: add `adapter/1` and `speech_options/1` clauses for
  `model: "morse-duplex"` that resolve to
  `Vxpipe.Providers.MorseCode.DuplexSTSSession`, and a `validate_speech/2`
  clause that calls its `configure/1`. Allowed options: the Morse keys plus
  `:output_transcript`. Reject `:clock` and `:yield?` from call specs; they
  stay test-only options passed by tests that start the provider directly.
- `Vxpipe.Providers.MorseCode` manifest: unchanged (`sts` stays the Morse STS
  session). The catalog routes by model.
- Tests: `plan_startup/sts_activation_test.exs` gains a case that the
  `morse-duplex` model resolves, starts, and declares the duplex facts; an
  unknown Morse model is rejected.

## Package 3 — aligned spoken prefix

Goal: when output is fenced or overlapped, the published agent text is exactly
the fragments whose audio was played.

Today `Capability.SpeechToSpeech.Output` keeps a single `pending_text` per
output and nothing reads the `audio_start_ms`/`audio_end_ms` fields on
`:output_transcript`.

Architecture:

- Add `fragments` to the active output (bounded: 256 fragments or 64 KiB of
  text; overflow fails the capability with `:output_text_overflow`).
- On `:output_transcript` with alignment fields for the active output, append
  `{audio_start_ms, audio_end_ms, text}`. Without alignment fields, keep the
  current `pending_text` behaviour.
- At settlement (`complete_playback/3` and the fence path), when fragments
  exist, publish the concatenation of fragments with `audio_end_ms <=
  played_ms`. With `played_ms == 0`, publish nothing (the existing zero-egress
  rule).
- Mark the published transcript with the existing egress-qualified evidence;
  do not claim remote hearing.

Tests (capability, Morse duplex with the manual clock):

- A fence after the first word publishes only that word.
- A fence before any playback publishes nothing.
- A completed output publishes all fragments.
- A provider without alignment fields keeps today's behaviour (Google and
  Morse STS suites unchanged).

## Package 4 — hold by muting

Goal: with `hold: :mute`, a hold keeps the provider session, its conversation
and in-flight tools; release resumes without reconnecting.

### Contract addition (record in the speech provider contract)

New optional STS callback, required when a descriptor declares `hold: :mute`:

```elixir
@callback set_input_hold(pid(), boolean()) :: :ok | {:error, atom()}
```

and `Speech.Session.set_input_hold(allocation, held?)` routed through the
channel like other commands. On `true` the provider stops sending caller
audio to the model and tells the model, in its own wire terms, that the caller
is on hold and cannot hear it. On `false` it resumes input and tells the model
the caller is back and nothing said during the hold was heard. The wording
belongs to the provider; the engine never supplies prompt text.

Descriptor validation: `hold: :mute` requires the provider module to export
`set_input_hold/2`.

### Capability changes (`Capability.SpeechToSpeech`)

In `handle_call(:hold, ...)`, branch on `state.descriptor.hold`:

- `:stop`: today's behaviour, unchanged.
- `:mute`: call `Session.set_input_hold(session, true)`; close input with
  `Input.hold/1`; fence and discard the active output (`fence_output/1`);
  reject queued responses; **do not** call `interrupt_tool_turns/1` or
  `ToolEvents.retire/1`, so in-flight tools continue; skip the
  `input_quiescent?` check, because the session is kept, not reused from
  idle. While held, discard any newly admitted output: `:response_started`
  is rejected by the existing held fingerprint.

In `handle_call({:release, epoch}, ...)` with `hold: :mute`, call
`Session.set_input_hold(session, false)` before reopening input.

A tool result that arrives while held is delivered to the provider as usual;
the provider decides when to speak it, and that speech is admitted normally
after release.

### Morse duplex

Implement `set_input_hold/2`: while held, ignore pushed audio and record
`{:hold, :started}` / `{:hold, :ended}` in a bounded test-visible context log
(exposed through `format_status/1` redaction rules, not a public API).

### Tests

- Capability: hold mutes, fences output, keeps a pending tool, and a tool
  result during hold is spoken after release; release sends `false` and the
  same provider process continues (monitor shows no restart).
- Capability: `hold: :stop` suites unchanged.
- Descriptor: `hold: :mute` without `set_input_hold/2` is rejected.

## Package 5 — compiled-room duplex proofs

Goal: prove checkpoint C's remaining tasks in real compiled rooms with the
Morse duplex provider under `clock: :realtime`. Use the
`sts_transcript_modes_test.exs` harness and its embedded PCM connection. Use
the default 60 ms Morse unit so replies stay short, and bounded
`assert_receive` timeouts (no sleeps).

Add `test/.../room_authority/sts_duplex_call_test.exs` with:

1. **Turn and transcript:** one caller utterance produces one
   `ParticipantTurnStarted`/`ParticipantTurnCompleted` pair with
   `endpointing: :inferred_gap`, one agent turn, and agent text published only
   after playback settlement.
2. **Overlap:** caller tone during the reply; the provider yields; the agent
   turn completes with outcome `:overlapped`; the published text stops at the
   last fragment whose audio played (package 3). Also a short backchannel
   (one short tone below the decoder's word threshold) does not stop playback.
3. **Soft onset:** a reply whose first frames are below the activation
   threshold is played in full (pre-roll).
4. **Hold:** a hold mutes, discards output, keeps a tool in flight; release
   resumes with the same provider process; the tool's result is spoken after
   release (package 4).
5. **Room fence prefix:** a policy denial mid-reply publishes only the aligned
   prefix; a denial before playback publishes nothing.
6. **Tool survives overlap:** a tool call starts, the caller talks over the
   reply, and the result still reaches the provider and is spoken.
7. **Exit:** the Gemini and Morse STS room suites pass unchanged.

This closes the `:overlapped` proof deferred from R7-4.

## Package 6 — OpenAI provider package

Goal: `openai` exists as a provider with a tenant API-key credential. It does
not advertise `:sts` until package 9's hosted check passes.

In `apps/vxpipe_providers/lib/vxpipe/providers/`:

- `openai.ex`: `Vxpipe.Providers.OpenAI`, `id/0` returns `"openai"`,
  `capabilities/0` returns `credential` and `credential_validation` only.
- `openai/credential.ex`: `auth_kind/0` `"api_key"`,
  `preview_fields/0` last four, `validate/2` like Google's (printable ASCII,
  at most 8,192 bytes).
- `openai/credential_validation.ex`: `request/2` returns
  `[url: "https://api.openai.com/v1/models", headers: [{"authorization",
  "Bearer " <> key}, {"accept", "application/json"}]]`.
- `registry.ex`: add `"openai" => Vxpipe.Providers.OpenAI`.

Credential readers: reuse the tenant credential storage and reader path from
[tenant provider credentials](milestones/tenant-provider-credentials-and-platform-configuration.md);
`authenticate_speech/2` already maps an `api_key` credential to the
`:api_key` private option. Record the new provider in
`docs/existing-provider-credentials.md`.

Tests: manifest and registry lookup, credential validation accepts and
rejects, validation request shape (no network), and redaction (the key never
appears in inspect output or logs).

## Package 7 — GPT-Live adapter over a fake socket

Goal: `Vxpipe.Providers.OpenAI.GPTLiveSession` implements `STSProvider` for
`model: "gpt-live-1"` and passes the full fake-socket matrix. No hosted call.

### Modules (in `apps/vxpipe_call_engine/lib/vxpipe/providers/openai/`)

| Module | Kind | Responsibility |
| --- | --- | --- |
| `GPTLive` | pure | Configuration (`new/1`, public options, descriptor) and the wire codec: encode client events, decode server events. |
| `GPTLiveSocket` | `Speech.Socket` behaviour | One WebSocket; sends JSON text frames; forwards decoded frames to its owner. Mirror `Google.STSSocket`. |
| `GPTLiveSession` | GenServer, `STSProvider` | Owns the session lifecycle and calls the pure modules. |
| `GPTLiveDelegation` | pure | Delegated tool state: open calls per delegation, when `response.create` may be sent, answering discarded calls. |
| `GPTLiveUsage` | pure | Voice-seconds deltas and backend token usage. |
| `GPTLiveHistory` | pure | Bounded seed history (package 8). |

The session also uses the shared `TurnInference`, `OutputSegmenter` and
`BurstResponses`.

### Configuration and descriptor

Public options: `model` (`"gpt-live-1"` only), `voice` (validated name, default
from the verified profile), `backend_model` (required string, pinned in the
plan), `input_sample_rate` and `output_sample_rate` (24,000 unless
`docs/sts-duplex-profile.md` verifies others). Private options: `api_key`,
`system_prompt`, `tools` (allowlisted function tools only; reject any other
tool type).

Descriptor: `kind: :sts`, `turn_control: "provider"`, `endpointing:
:inferred_gap`, `speech_start?: true`, `response_start?: true`,
`output_shape: :continuous`, `barge_in: :provider`, `continuity:
:history_reseed`, `tool_cancellation?: false`, `hold: :mute`,
`history_reconciliation?: false`, input and output PCM16 mono formats.

### Wire mapping

Client events (send):

| Trigger | Event |
| --- | --- |
| Socket connected | `session.start` with model, voice, `audio.format`, `instructions`, `input` (seed history), `delegation` (`type: "responses"`, `responses.model`, `responses.tools`), `store: false` |
| `submit_input(..., {:audio, pcm})` | `input_audio.append` (base64) |
| `submit_input(..., {:text, ref, text})` | `session.commentary.append` (spoken) |
| `set_input_hold(true/false)` | `session.input_audio.mute` / `unmute`, then `session.thinking.append` with the hold or return note |
| Tool result | `response.item.create` with `function_call_output`, then `response.create` when the delegation has no open calls |
| `close/1` | `session.close`, then wait for `session.closed` (bounded 10 s) |

Wait for `session.started` before sending audio or commands.

Server events (receive):

| Event | Handling |
| --- | --- |
| `session.started` | Emit `:ready`. |
| `session.input_transcript.delta` | `TurnInference` fragment; emits `:speech_started`, `:input_transcript`, `:turn_ended` with `:inferred_gap`. |
| `session.output_transcript.delta` | `OutputSegmenter` fragment for alignment. |
| `session.output_audio.delta` | Decode base64 PCM and feed `OutputSegmenter` in 20 ms frames; bursts go through `BurstResponses`. |
| `session.delegation.created` | Record the delegation (Responses target only; a client target fails explicitly, since client delegation is out of scope). |
| `response.event` → `response.output_item.done` (function call, completed) | `GPTLiveDelegation.call_arrived/2`; emit `:tool_call` with the current context. |
| `response.event` → `response.completed` | Backend usage; allow `response.create` when no calls are open. |
| `response.event` → `response.failed` / `response.incomplete` | Discard that delegation's open calls. |
| `session.usage.updated` | Voice-seconds delta through `GPTLiveUsage`. |
| `session.closed` | By reason: `close_requested` and `remote_hangup` end normally; `content` fails with `:moderation`; `expired` and `connection_lost` go to package 8. |
| `error` | Match `client_event_id`; a fatal code fails the session with a closed reason; others are logged without payloads. |

Clocks: the input clock is the audio pushed so far; the output clock is the
decoded output bytes so far (at 24 kHz PCM16, `ms = bytes / 48`). Output
transcript fragments carry the session timeline; `OutputSegmenter` anchors
them to each burst's audio.

Tool calls the channel discards (`:discarded` from `emit`, R11-1) must still
be answered: send a `function_call_output` saying the action is no longer
permitted, so the delegation does not block later calls.

### Tests (fake socket, JSON fixtures)

Put fixtures under `test/support/fixtures/gpt_live/` as JSON lines. Cover:
startup ordering and `store: false`; audio round trip; caller turn inference
from real fragment cadence; two bursts from one answer; overlap with
self-yield; discarded bursts; delegated tools (single, multiple pending,
duplicate call ID, failed and incomplete responses, discarded call answered);
usage deltas and backend usage; every close reason; malformed and unknown
events; credential, audio and transcript redaction in `format_status/1`, logs
and crash reports. Drive at least the audio, turn, burst and tool cases
through the real STS capability, as the Google controller tests do.

## Package 8 — session continuity and lifecycle

Goal: checkpoint E. A dropped or expired GPT-Live session is replaced by one
seeded with the text the room actually published.

### Contract addition (record in the speech provider contract)

New optional STS callback, required when a descriptor declares `continuity:
:history_reseed`:

```elixir
@callback append_history(pid(), {:caller | :agent, String.t()}) :: :ok | {:error, atom()}
```

and `Speech.Session.append_history(allocation, entry)`. The room acknowledges
an accepted final caller transcript after the router approves its route to
the virtual agent, or a playback-settled agent transcript after delivery to
the human connection. The capability then calls the session callback. Only
room-authorized caller text and delivered agent text enter history. The
room-boundary correction is recorded in [the decision](gpt-live-room-history.md).
On a lost session, the provider waits for a speech-channel, capability and
room publication barrier before taking its bounded snapshot. The reconnect
deadline includes that wait; failure to complete it fails reseed.

### Provider behaviour (`GPTLiveHistory`, pure)

- Keep a bounded ring: at most 128 messages and an estimated 8,192 tokens
  (estimate 4 bytes per token, rounding up), trimming the oldest first.
- On `expired` or `connection_lost`: start one replacement socket within a
  5-second deadline and send `session.start` with the ring as `input`.
  Failure or a missed deadline fails the capability with `:reseed_failed`.
- Resume rule after a reseed: if the drop came while a burst was active, or
  after a caller turn ended with no burst since, send
  `session.commentary.append` asking the model to say briefly that the line
  cut out and continue from the last heard text. Otherwise send nothing and
  wait for the caller.
- Reset `TurnInference`, `OutputSegmenter` and the clocks; keep
  `BurstResponses`' latest context (a new context arrives with the next
  input). Start a new usage count per session.
- In-flight delegated work belongs to the lost session. Invocations the room
  already started still finish; their results are appended as history.
- Duration renewal: no limit is documented (`docs/sts-duplex-profile.md`), so
  the renewal task is not applicable. Record that as a note on the E task.
  Do not implement renewal speculatively.

### Transfers

A completed transfer stops the session (existing teardown). A failed transfer
releases the hold with the same session (package 4). Amendment 2 adds the
missing STS tool path: the room submits an allowlisted provider-originated
`transfer` call through the participant-transfer invocation, carrying the
current STS capability and caller identity in its tool context. Test committed
teardown and failed-transfer recovery from a provider-originated call with
both Morse duplex and the fake GPT-Live socket.

### Morse duplex

Implement `append_history/2` with the same bounded ring, and a test-only
option to script `:expired` and `:connection_lost` closes, so the capability
reseed path runs locally.

### Tests

Reseed on both close reasons with the seeded history asserted; the resume
rule's three cases (mid-burst, unanswered caller turn, idle); reseed failure
and deadline expiry; the ring's trimming bounds; a completed transfer stops
the session and a failed transfer resumes it. Run the lifecycle cases with
both the Morse duplex provider and the GPT-Live fake socket.

## Package 9 — documentation, Console setup, load, review, hosted check

Local checkpoints precede the hosted check, which needs separate billable
authorization.

### Local checkpoints

- Docs: add the duplex profile, burst-to-response mapping, `set_input_hold/2`
  and `append_history/2` to `docs/speech-provider-contract.md`; add an author
  example to `docs/speech-integration-guide.md`; add OpenAI to
  `docs/provider-integration-packages.md`.
- Console: add an `openai` entry to
  `apps/vxpipe_console/assets/src/admin/setupCatalog.json` with one API-key
  field and LLM plus speech-to-speech capabilities. The user requested full
  local enablement on 2026-09-26, overriding the prior badge gate. Test the
  installed-capability intersection and inspect the rendered setup page with
  `agent-browser` at desktop and mobile widths.
- Load: add a `:sts_duplex` mode to `call_load_test.exs` using the Morse
  duplex provider under the real-time clock; run the ten-call lane in a quiet
  window and keep the reports with the evidence.
- Review and gates: an independent implementation review of the whole
  milestone, then the five root gates.

### Hosted check (only with explicit billable authorization)

Add `test/integration/gpt_live_hosted_test.exs` with `@moduletag
:integration`, `@moduletag :hosted`, a 120-second timeout, and `skip` unless
`VXPIPE_LIVE=1` is set. Require `OPENAI_API_KEY` when selected. Keep the budget
short and fixed (at most five sessions, three minutes of voice).

Automated scenarios: a short turn; caller speech during a reply (the model
yields); a tool call and its spoken result; hold and release by muting; a
forced reconnect with reseed. Resolve each unverified item in
`docs/sts-duplex-profile.md`.

Manual phone scenarios over a real Twilio or Telnyx leg, recorded in the
labnote: a backchannel does not stop the agent; a real interruption does;
speakerphone echo does not make the agent react to its own voice.

The manifest `:sts` entry, `CapabilityCatalog` adapter and Console `s2s` badge
are already enabled by the user's direction. The hosted check still determines
whether the milestone's phone interoperability acceptance is complete.

## Package 10 — docs site homepage test (R10-2)

In a separate docs commit, update
`vxpipe-docs/test/homepage-structure.test.mjs` to the current page: two hero
buttons, the current trust badges, and the current section order. Keep the
checks minimal and run `node --test` in `vxpipe-docs`.

Completed in the separate docs commit `97e5c0af`; the current docs-site
`node --test` lane passes eight tests.

## Contract changes this plan introduces

| Change | Package | Record as |
| --- | --- | --- |
| `set_input_hold/2` callback and `Session.set_input_hold/2` | 4 | Speech provider contract; descriptor rule |
| `append_history/2` callback and `Session.append_history/2` | 8 | Speech provider contract; descriptor rule |
| `morse-duplex` model under the `morse` provider | 2 | Catalog note; no specification change |
| Duration renewal not applicable (no documented limit) | 8 | Note on the E task, citing `docs/sts-duplex-profile.md` |

None of these changes the frozen specification's behaviour, so no amendment
is needed. If an implementation finding forces a behavioural change, record
an amendment in the milestone's status section first.

## Risks

- The unverified GPT-Live items (connection headers, other audio formats,
  talk-over behaviour, continuous output silence, duration limit, 24 kHz
  conversion) are resolved only by the hosted check. Build against the
  documented facts and keep each assumption in one place (`GPTLive`).
- Echo on carrier lines can only be judged on real calls.
- The parent [Agent speech-to-speech](milestones/agent-speech-to-speech.md)
  milestone is still open (R1-4). Changes to shared capability code in
  packages 3, 4 and 8 must keep its suites green.
