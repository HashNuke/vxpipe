# GPT-Live duplex contract

## Task

Implement the [GPT-Live speech-to-speech
milestone](../docs/milestones/gpt-live-speech-to-speech.md) beyond its frozen
specification. This labnote covers checkpoint A; later checkpoints get their own
sections or notes.

## Checkpoint A — verified API profile and contract facts

### API profile

Fetched OpenAI's published GPT-Live guides (getting started, WebSockets,
managing sessions, delegation, server-side controls, prompting) plus the model
card. Recorded the documented facts and the residual unknowns in
`docs/sts-duplex-profile.md`. Key verified points:

- Primary URL `wss://api.openai.com/v1/live/sessions`, bearer API key, send
  `session.start` first and wait for `session.started`.
- WebSocket formats: PCM16 24 kHz (default) / 16 kHz, G.711 μ-law 8 kHz, G.711
  A-law 8 kHz; one format for input and output.
- Startup history up to 128 messages / 8,192 tokens; `instructions` up to
  16,384 tokens; appends capped at 500 tokens each.
- Primary WebSocket output audio has **no timing fields**; only sideband
  reflection carries `start_ms`/`end_ms`. The adapter must gate/segment audio
  itself.
- `session.input_audio.mute`/`unmute` plus `session.thinking.append` give the
  hold semantics the milestone needs (session and backend work continue).
- Delegation: read `function_call` from nested `response.output_item.done`;
  return `response.item.create` then one `response.create`. `response.completed`
  carries an empty output array.
- Usage `usage.seconds` is cumulative; `session.closed.reason` is
  `close_requested | expired | content | remote_hangup | connection_lost`.
- Talk-over is full duplex and the prompt tells the model to yield on a real
  interruption; backchannels are separate. No yield event exists, so the
  adapter infers it from output audio stopping.

Six items remain unverified and are checkpoint F hosted-check items: extra
connection headers, nonstandard `audio.format`, talk-over/echo on a carrier,
continuous output silence, any numeric duration limit, and 24 kHz
down-conversion. Because no duration limit is documented, checkpoint E's
"renew before the documented limit" task has no numeric target yet.

### Contract changes

`Speech.Descriptor` (new closed facts, defaults = existing room-owned
behavior): `output_shape: :turns | :continuous`, `barge_in: :room | :provider`,
`continuity: :resumption_handle | :history_reseed | :none`,
`tool_cancellation?`, `hold: :stop | :mute`, and `endpointing: :inferred_gap`.
Validation: `:inferred_gap` only for `turn_control: "provider"` with
`speech_start?`; `barge_in: :provider` requires `history_reconciliation?:
false`; non-STS descriptors must keep the defaults. Gemini and Morse STS
descriptors keep the defaults and still validate.

`Speech.Event`: `:turn_ended`/`:eager_turn_ended` accept `:inferred_gap`;
`:output_transcript` accepts an optional complete
`output_ref`/`audio_start_ms`/`audio_end_ms` span. `AgentTurnCompleted` gains
`outcome` (`:completed | :overlapped`); `ParticipantTurnCompleted` gains
optional `endpointing`. Both project into the archive payload.

### Red-green evidence

- Wrote `test/vxpipe/call_engine/speech/sts_duplex_contract_test.exs` first;
  it failed with `KeyError :barge_in`, `Event.build` rejecting `:inferred_gap`,
  and the public-projection assertion failing. After implementation all 9 pass.
- Full `vxpipe_call_engine` suite: 1,523 tests, 0 failures, 30 excluded
  (seed 0). Gateway `turn_state`: 5 tests, 0 failures.
- `mix compile --warnings-as-errors` clean after formatting.
- One combined focused run had a single `speech_to_text_test.exs:496` timing
  failure that passes in isolation; pre-existing load sensitivity, not this
  change.

## Checkpoint B — shared duplex modules (partial)

Implemented the two provider-neutral pure modules that the Morse duplex provider
and the GPT-Live adapter share.

### `Speech.Duplex.TurnInference`

Opens a caller turn on the first non-empty input fragment (emitting
`:speech_started` then a partial `:input_transcript`), accumulates fragment text
exactly, closes on pushed caller audio reaching the gap or on a timeline gap
larger than the gap, ignores empty fragments, and closes on `finish/1` at
session end. All durations are audio time; no timers. Emits
`{kind, fields}` tuples carrying the generated `turn_ref`, ready for
`Event.emit/3`, with `endpointing: :inferred_gap` on `:turn_ended`.

Tests: `test/.../duplex/turn_inference_test.exs`, 7 tests red then green
(quiet-audio close, timeline-gap close and reopen, overlapping, empty, session
end, malformed input).

### `Speech.Duplex.OutputSegmenter`

Frame-based energy gate with hysteresis over PCM. Opens a burst on an active
frame, replays a bounded pre-roll so quiet onsets survive, keeps pauses shorter
than the gap inside the burst, forwards burst audio and closes after the gap.
`{:open, ref}` asks the adapter to admit an output; while awaiting admission it
buffers burst audio up to `buffer_ms` and returns `{:error, :buffer_overflow,
state}` rather than blocking. Fragment alignment keys the first fragment to the
burst (fixing the provider-to-output offset), reports later fragments with
`audio_start_ms`/`audio_end_ms` relative to the output, attaches late fragments
to the earlier output, and drops/counts fragments with no matching audio after
`fragment_timeout_ms`.

Tests: `test/.../duplex/output_segmenter_test.exs`, 9 tests red then green
(burst open/close, short pauses, pre-roll-only silence, quiet onset, overflow,
first-fragment offset, late attachment, unmatched drop, bad config).

### Evidence and state

- Both duplex test files pass 16 tests, 0 failures (seed 0).
- `mix compile --warnings-as-errors` and `mix credo --strict` (1,109 files, no
  issues) are clean.
- Full umbrella gate `PGHOST=/var/run/postgresql mix test --seed 0` passes
  2,726 tests, 0 failures; `mix format --check-formatted` and
  `mix deps.unlock --check-unused` also pass.
- Not done: wiring either module into `MorseCode.DuplexSTSSession` (checkpoint
  B tasks 3–4), so the module boxes are checked but the checkpoint exit stays
  open. An unreferenced module plus tests keeps the umbrella usable.

## Checkpoint B — complete

Wired the shared modules into a local provider.

- `Provider.MorseCodeDuplex.Session` + `Providers.MorseCode.DuplexSTSSession`
  reuse the Morse codec, `TurnInference` and `OutputSegmenter`, declare the
  duplex descriptor facts, and use the legacy `:turn_ended` → `admit_output`
  path (no response contexts). Output is segmented; each burst is admitted once
  and submitted under one outstanding credit.
- Reply generation is queued behind a draining interrupted output. An admit
  that arrives while the previous output drains is stashed and replayed when the
  queued reply starts.
- Capability proof `capability/speech_to_speech_duplex_test.exs` (3 tests): one
  caller turn → one segmented reply with playback-settled `"RECEIVED HI"`
  transcript and a `:milliseconds` `:speech_to_speech` usage observation; and
  `TOOL echo {...}` → result → `"RECEIVED ok"` reply.
- Self-yield proof `speech/duplex_sts_conversation_test.exs`: while one output
  credit is held, caller tone makes the provider finish the interrupted reply
  (its `:output_completed` follows the released credit) with no engine fence.
  The eager provider cannot overlap through the capability because generation
  completes as fast as credits return; the direct-session test uses credit
  backpressure instead, deterministically and without sleeps.

Evidence: `capability` + `speech` suites pass 504 tests, 0 failures (seed 0).

## Checkpoint C — partial

- `Capability.SpeechToSpeech.handle_event/2`: caller onset with an active
  output no longer fences when the descriptor declares `barge_in: :provider`.
  Existing barge-in-room behavior is unchanged.
- `RoomAuthority.SpeechToSpeech`: an overlapping caller onset marks the open
  agent turn, and `handle_turn_completed/5` publishes
  `AgentTurnCompleted.outcome` as `:overlapped` (default `:completed`).
- `CallerTurns` carries the inferred boundary evidence onto the public
  `ParticipantTurnCompleted.endpointing`.
- Focused room unit tests prove both outcomes (`speech_to_speech_test.exs`, 20
  tests, 0 failures).

Still open: the compiled-room duplex proof, per-fragment playback truncation,
pre-roll soft onset at the room, `hold: :mute`, room-fence prefix, and tool
survival across overlap.

## Review-response rework (R1-1, R2-1..R2-4, R3-1)

Addressed the review-agent follow-up in order:

- **R2-2 / Amendment 1** — the duplex descriptor facts are now STS-only. The
  descriptor defaults them to `nil`, non-STS descriptors must not declare them,
  and each STS provider declares them explicitly: Google STS
  `continuity: :resumption_handle`; Morse STS `continuity: :none`; Morse duplex
  keeps its duplex facts. `default_duplex_facts?/1` is gone.
- **R2-3** — `OutputSegmenter` keeps the shared 800 ms gap; the Morse duplex
  provider uses the shared defaults unchanged (2 s receive buffer, 300 ms
  pre-roll) with no overrides. Morse word gaps stay under 800 ms, so a reply is
  one burst without tuning the module.
- **R3-1 (reopened B)** — the provider now emits a continuous, clock-paced
  stream: leading silence, the Morse reply, trailing silence. `advance/2` drives
  the clock. Silence before a burst is discarded; the pre-roll replays the real
  sub-threshold leading silence; pre-admission output overflows the 2 s buffer
  and fails the session explicitly. Provider-level tests cover self-yield,
  silence discarding + pre-roll, and overflow.
- **R1-1** — added a red-green capability test for `barge_in: :provider`: with
  a fake that does not self-yield, caller onset leaves the output active (no
  interruption) while a policy denial still fences it. Removing the branch makes
  the test fail, confirmed by a temporary revert.
- **R2-1** — recorded the schema versioning rule in the milestone status: the
  additive `outcome`/`endpointing` fields stay in schema version 1; consumers
  treat missing fields as `:completed`/`nil`.
- **R2-4** — added and changed test counts are reported separately below.

Evidence: affected `speech`, `capability`, `room_authority` and `providers`
suites pass 806 tests, 0 failures (seed 0). Added tests this rework:
`duplex_sts_conversation_test.exs` grows to 3, and
`speech_to_speech_duplex_test.exs` grows to 3; changed:
`sts_duplex_contract_test.exs`, `sts_provider_contract_test.exs`,
`descriptor`/provider `configure` sites.

The explicit Google STS facts pushed `Google.STSSession` past Credo's 800-line
limit, so its two identical PCM format maps moved to `Google.STS.pcm_format/1`
(790 lines now). No behavior change.

## Review-4 response (R4-1, R4-2, R2-3)

Review 4 confirmed the earlier fixes and found that the Morse duplex provider
had no clock of its own: only tests called `advance/2`, so a compiled room or
the load lane would never tick it. Review 5 proposed a validated
`:realtime`/`:manual` clock.

- `MorseCodeDuplex.Clock.frames_due/5` is a pure drift-corrected scheduler.
  Frames come from a monotonic origin, not a tick count, with a bounded
  catch-up; a longer backlog moves the origin and reports a stall.
- The provider defaults to `clock: :realtime`: it owns a 20 ms `send_after`
  timer with a clock generation, cancels it on close, and rejects `advance/2`
  under realtime. `clock: :manual` keeps the deterministic test clock. Both
  share the same frame-emission path.
- `yield?: false` and `clock: :manual` are documented under a "Test options"
  heading; GPT-Live always decides whether to yield.
- Normalized the provider-option key lookup as `MorseCode.Config.option_keys/0`
  across all four Morse sessions, replacing the runtime
  `Map.keys(Config.__struct__()) -- [:__struct__]` idiom.

Added tests: `clock_test.exs` (4), plus two provider-level clock tests and one
realtime capability test. Changed: the duplex provider, its capability and
provider tests to opt into `clock: :manual`. The full call-engine suite passes
1,554 tests, 0 failures (seed 0).

## Review-6 response (R6-1..R6-6)

Fixed the six code-review findings in the Morse duplex provider:

- R6-1: one output per reply, with later bursts continued under the same output
  (the room has one output slot per turn). `open_burst/2` admits each new burst
  and flushes its audio; inter-burst silence is dropped per the segmenter spec.
- R6-2: segmenter thresholds derive from `config.amplitude`; amplitudes below 2
  are rejected at configuration.
- R6-3: a reply that yields before admission is remembered and completed as
  `:interrupted` when its admission arrives.
- R6-4: a bounded FIFO replaces the single queued reply; overflow fails the
  session explicitly.
- R6-5: tool replies are sanitised, length-bounded and encoded before
  `turn_ended`; encoding failure stops the provider.
- R6-6: input fragments are fed on partials as contiguous audio-time slices so
  caller onset reaches the room while the reply is open and the caller turn is
  not split by sparse timing.
- `interrupt/2` also cancels queued/yielded-pending replies instead of
  returning `:stale_request`.

Added tests: two provider clock-adjacent amplitude/multi-burst/admission tests,
two queued-reply and truncation capability tests, and the review-6 provider
cases. The affected `speech`, `capability`, `room_authority` and `providers`
suites pass 815 tests, 0 failures (seed 0).

The provider grew past Credo's 800-line limit, so its pure configuration moved
to `MorseCodeDuplex.Profile` (descriptor facts, PCM format, segmenter options)
and its tool trigger/summary handling to `MorseCodeDuplex.ToolReply`. The
session keeps the GenServer and the output state machine and is 769 lines.

## Review-7 response (R7-2, R7-4; R7-1/R7-3 planned)

- R7-2: a yielded-before-admission reply now emits `:interrupted` and then
  `:output_completed` for its admitted reference, releasing the room slot; the
  test settles it and admits the next reply.
- R7-4: added provider tests for the FIFO overflow (`:pending_reply_overflow`)
  and for a tool result that sanitises to nothing (`:empty_tool_reply`), both
  stopping the provider explicitly. The `:overlapped` proof stays in C.
- R7-1/R7-3: confirmed `ResponseOrigins` accepts a stored context for later
  `:response_started` events while its fingerprint is current, so no amendment
  is needed; the frozen spec already requires per-burst outputs. The
  `response_start?: true` redesign remains. A tractable shape: keep one output
  slot but emit `:response_started` per burst and pause the clock after a burst
  closes until `:vxpipe_speech_output_settled` for it arrives, so bursts
  serialize and no multi-in-flight machinery is needed.

## Review-8 response (R8-1, R8-2, R8-3)

- R8-1: `ResponseOrigins.submit/2` prunes accepted contexts whose fingerprint
  is stale before choosing a candidate, keeping contexts a pending response
  references (and the external activity origin). Added
  `response_origins_test.exs` proving stale unreferenced contexts are dropped,
  current and referenced ones kept, and capacity is freed.
- R8-2: an empty sanitized tool summary now speaks `"RECEIVED OK"` instead of
  stopping the provider; the explicit failure stays for a reply that cannot be
  encoded.
- R8-3: the R7-2 `:output_completed` emit now stops the session on failure.

R7-1/R7-3 (`:response_started` per-burst redesign) remain and are the next step
now that R8-1's prerequisite is fixed.

## Review-9 response (R9-2, R9-3; R9-1 pending on R7-1)

- R9-2: removed the dead external-activity retention clause from
  `ResponseOrigins`; `Input` stores a fingerprint there, not a context
  reference.
- R9-3: pruning now runs only when a new candidate context is needed, not on
  every frame; `fingerprint/1` is private again and the hand-built unit test
  was removed.
- R9-1: the requested behaviour test needs a `response_start?: true` provider,
  which arrives with the R7-1 redesign, so it is deferred to that.

Also committed the user's in-progress `vxpipe-docs` landing/visual refresh as
its own commit; the separate homepage-structure test was already failing at the
parent commit.

## Full gate evidence

All five root completion gates pass on the A + B + C-partial worktree
(`GATES_EXIT=0`): `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict` (12,512 mods/funs, no
issues), `PGHOST=/var/run/postgresql mix test --seed 0` (2,731 tests, 0
failures across all children), and `mix deps.unlock --check-unused`.

## Remaining work (not started)

- **C remainder:** compiled-room duplex proof, per-fragment playback
  truncation, room-level pre-roll soft onset, `hold: :mute`, room-fence
  prefix, tool survival across overlap.
- **D:** `Vxpipe.Providers.OpenAI` package + tenant API-key reader,
  `GPTLiveSession` + private socket, fake-socket fixture matrix, redaction
  proof.
- **E:** reseed/renewal/lifecycle with both local providers.
- **F:** provider/author docs, Console gated option, hosted carrier check
  (needs explicit billable authorization), ten-call load lane, rendered-browser
  inspection, independent review.

## Decisions and barriers

- Followed the milestone literally that existing STS providers declare the first
  value in each new fact row, so the new struct defaults reproduce current
  behavior without editing Gemini or Morse STS `configure/1`.
- Kept the new public-event field additions optional and only added
  `endpointing` to the archive payload when present, to avoid perturbing every
  existing participant-turn fact.
- Barrier: the milestone's checkpoint A named an unverified API surface; the
  official pages are reachable, so verification succeeded. The remaining
  unknowns are genuinely undocumented on the pages checked.

## Next

Checkpoint B: pure `Speech.Duplex.TurnInference` and
`Speech.Duplex.OutputSegmenter` modules with PCM fixtures, then
`MorseCode.DuplexSTSSession` through the real capability.
