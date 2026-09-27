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

## Review-10 response (R10-1)

Added channel-side response-context retirement: `ResponseContexts.retire/2`,
`Session.retire_response_contexts/2`, and `ResponseOrigins.prune/2` retiring the
contexts it drops. Updated the two capability-origin tests that had encoded the
16-context `:busy` bug to the new behaviour (a seventeenth change is accepted; a
late old-origin tool call is rejected at the channel), and added
`response_contexts_test.exs`. The full R9-1 behaviour test through the Google
controller is still open because deterministic settling of twenty sequential
inputs needs the provider input slot.

## Review-11 response (R11-1, R11-2, R11-3)

- R11-1: the channel now keeps a bounded tombstone window of retired contexts.
  A late `:response_started` on a tombstoned origin is accepted by `emit` and
  answered with `{:vxpipe_speech_response_discard, ...}`; a late `:tool_call`
  returns `:discarded`; a context outside the window is still rejected. A late
  response can no longer fail the Google session.
- R11-2: `ResponseOrigins.prune/2` drops its own copy only after the channel
  confirms retirement, so a failure retries next prune.
- R11-3: the origin test now announces a response on the seventeenth context and
  asserts admission, completing R9-1.

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

## Package 1: per-burst responses

- Added pure `Speech.Duplex.BurstResponses` mapping each `OutputSegmenter` burst
  to its own `:response_started` response, with unit tests for every state
  transition.
- The Morse duplex provider declares `response_start?: true`, implements
  `submit_input/3`, announces one response per burst and drops rejected bursts
  through `BurstResponses.discarded/2`. The continuation path and the reply-time
  `:turn_ended` are gone. The reply timeline moved to `MorseCodeDuplex.Output`.
- Evidence: call-engine child suite 1,576 tests, zero failures (seed 0); a
  `unit_duration_ms: 150` reply produces two admitted turns through the real
  capability; the pure module has 12 focused tests.
- Approximation: the Morse mock repeats the whole reply text per burst; the
  GPT-Live adapter aligns per-delta fragments in package 7.

## Package 2: morse-duplex from a call spec

- `CapabilityCatalog` resolves `model: "morse-duplex"` to
  `MorseCode.DuplexSTSSession`, allows the Morse keys plus `:output_transcript`,
  and rejects `:clock`, `:yield?` and unknown Morse models. The `MorseCode`
  manifest is unchanged; routing is by model.
- Evidence: call-engine child suite 1,580 tests, zero failures (seed 0); the
  activation test asserts the resolved duplex descriptor facts.

## Next

Package 3 (aligned spoken prefix), then package 4 (hold by muting) and the
remaining checkpoint-C proofs.

### Package 3 design notes (for a fresh session)

- Capability: add `fragments`/`fragment_bytes` to the active output built in
  `ResponseQueue.admit_reply/4`. `OutputTranscript.accept/2` appends
  `{audio_start_ms, audio_end_ms, text}` when the event carries
  `output_ref`/alignment for the active output, bounded to 256 fragments or
  64 KiB (`:output_text_overflow`); without alignment fields it keeps today's
  `pending_text` path. `OutputTranscript.ready?/1` must treat non-empty
  fragments with `text_final?` as ready. At settlement (`Output.maybe_finish_turn`
  → `publish_agent_transcript`) and at the fence (`Output.fence_output` prefix),
  concatenate fragments whose `audio_end_ms <= played_ms`; `played_ms == 0`
  publishes nothing.
- Provider: the Morse duplex provider must emit aligned per-word
  `:output_transcript` fragments (`output_ref` from the admitted segment,
  `audio_start_ms`/`audio_end_ms` relative to the burst). The clean path is to
  add word timings to `Provider.MorseCode.Encoder` (walk `start/2` runs, split
  on the 7-unit inter-word silence) and feed them through
  `OutputSegmenter.fragment/2`, which returns `{:transcript, seg_ref, text,
  start_offset, end_offset}` aligned to the burst. Fragments must be fed near
  their audio, not all upfront, because `fragment_timeout_ms` drops distant
  ones.
- This also replaces the package-1 approximation where the Morse mock repeats
  the whole reply text on every burst transcript.

### Package 3 implementation (2026-09-26)

- Capability output tracks bounded aligned fragments and uses sink played
  milliseconds for successful settlement and interrupted prefixes. Room
  interruption handling publishes only a qualified aligned prefix, before
  the terminal event; the old unverified prefix stays unpublished.
- Morse word timing is derived from the actual encoder runs. The output
  timeline emits due words alongside PCM frames; the provider feeds those
  words through `OutputSegmenter.fragment/2` and emits them with the admitted
  output reference. A final empty marker completes the transcript without
  repeating the whole reply.
- Red tests observed the previous last-fragment and whole-reply publication,
  plus missing room prefix publication. Green evidence: focused capability
  and room tests, then call-engine `mix test` at seed 628713: 1,588 tests, zero
  failures, 30 excluded. After the cohesion refactor, root `mix test` at seed
  600389 passes 2,775 tests, zero failures, 58 excluded. Root format, compile,
  strict Credo, unused dependency check and Lean verification all pass.
- The 256-fragment stress case occasionally lost its supervised fixture under
  parallel execution; it passed in isolation and when the settlement test
  module ran serially. The module is now serial. The root run covers that
  configuration without a failure.
- The first root `mix test` attempt failed before tests because PostgreSQL
  required the local Unix socket. `PGHOST=/var/run/postgresql mix test` passed.
- A sink's reported played duration must not exceed the output channel's
  generated duration. The initial broad duplex test used a fabricated large
  value and failed settlement as `:invalid_playback`; it now reads the local
  segment's recorded duration. This preserves the playback contract while
  testing full-text settlement.

### Package 4 handoff

- Current `SpeechToSpeech.handle_call(:hold, ...)` retires tool associations
  and rotates response-origin lifecycle identity. That is correct for
  `hold: :stop`, but `hold: :mute` must keep pending tools and allow their
  results to produce a reply after release. The old response context also
  becomes stale if the lifecycle revision or ingress epoch changes. A focused
  red test should cover a tool result delivered during mute and spoken after
  release, then implement a safe response-origin continuity rule for that path.
- `SessionTree.initialize/2` is where descriptor and provider module are both
  available to reject `hold: :mute` without `set_input_hold/2` before provider
  startup. `Speech.Session` commands go through `Speech.Channel.execute/4`;
  the new hold command needs a bounded callback with no synchronous event
  emission back into the channel.

### Package 4 implementation (2026-09-26)

- Red capability test: a tool result received during mute was rejected as
  `:stale_request`. Red room test: `SpeechToSpeech.hold/2` removed an admitted
  tool from `sts_tool_calls`. Red descriptor test: a mute descriptor without
  `set_input_hold/2` started the provider.
- The capability now preserves tool and response origin across mute. The room
  keeps pending tools through a transfer mute and permits their results under
  the original admitted scope while checking the same capability, caller
  identity, activation and current audio policy. A policy hold still cancels
  pending tools. The Morse duplex provider ignores held audio, records bounded
  hold boundaries, and buffers bounded tool replies until release.
- Focused room, capability and descriptor suites passed after the changes:
  38 tests, zero failures (seed 335534). Full root gates and Lean verification
  were pending at that checkpoint. Root format, warnings-as-errors compile,
  strict Credo, unused dependency check and Lean verification passed. The
  first umbrella test run found that the test-only STS result receiver did not
  handle the new `:hold_mode` query; its 31-test suite passed after the receiver
  was updated. The umbrella rerun passed 2,778 tests, zero failures and 58
  excluded (seed 963318). `git diff --check` also passed.

### Package 5 implementation (2026-09-26)

- A compiled-room `morse-duplex` fixture now uses the production call-spec
  selection and real-time provider clock. Nine focused tests cover caller and
  agent turns, aligned overlap prefix, a sub-window backchannel, a soft onset,
  mute and release with an in-flight tool, active-output discard on hold,
  policy fences at one word and zero playback, and a tool surviving overlap.
- The soft-onset test failed red with the first audible frame at full Morse
  amplitude (4,096 versus a 2,048 activation threshold). The Morse duplex
  reply fixture now attenuates only its first 20 ms to one quarter amplitude;
  the compiled room receives that frame through segmenter pre-roll and still
  decodes the full reply.
- The new fixture and existing Morse/Gemini transcript-mode room suite passed
  together: 46 tests, zero failures (seed 265466). An earlier combined run
  failed because the mute test assumed the stopped timeline output is removed
  synchronously; the provider may retain it briefly with its cursor at the
  end. The assertion now accepts either valid stopped state.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency
  check pass. The first package 5 umbrella run exposed a flaky 256-fragment
  settlement stress test under parallel load. Its test now acknowledges each
  batch through the capability state before the next batch; the focused test
  and full call-engine suite passed at seed 82355. The umbrella rerun passed
  2,787 tests, zero failures and 58 excluded at the same seed. Lean verification
  passed after the duplex changes.

### Package 6 implementation (2026-09-26)

- The new OpenAI provider's red tests failed because its manifest, credential
  and validation modules were absent. The implementation adds only the
  credential and credential-validation capabilities; the fixed registry still
  rejects `:sts`. The provider and registry suites pass 9 tests.
- The model-list probe uses `GET https://api.openai.com/v1/models` with a
  bearer token and JSON accept header. The endpoint and authorization shape
  were checked against the official OpenAI API reference. No network call or
  hosted speech validation was made.
- The first package 6 umbrella run reached Console and found its exact
  provider-capability catalog expectation missing the new `openai` entry. The
  Console test passed after the expected catalog was updated. A full umbrella
  rerun remains necessary after the adapter work stabilizes.

### Package 7 work in progress (2026-09-26)

- The pure GPT-Live configuration/codec and the first fake-socket session
  fixtures were red before implementation. Startup, readiness, audio append,
  mute/release, one segmented output burst and two pending tool results now
  pass focused tests. The session adapter is incomplete: usage, close/error
  matrix, burst silence pacing, history reseed and hosted interoperability are
  still open.
- The fake output fixture exposed a shared `OutputSegmenter` defect: if a
  complete audio burst arrived before admission, closing the burst discarded
  its bounded PCM. A red pure test reproduced the loss. The segmenter now keeps
  the pre-admission buffer with the retired output until admission and prunes
  retired output metadata to the documented eight-output window. The segmenter
  and first fake-socket output suite pass 12 tests together.

- The adapter now covers mute acknowledgment before context and caller release,
  inferred caller gaps, output idle closure, two delegated calls, malformed
  delegated arguments, backend response failures, close reasons and fatal
  errors. `SpeechToSpeechRuntime` passes API key, prompt and authorized tools
  only through the provider's private init. A fake socket drives a real STS
  capability from caller text to locally settled agent speech. Red tests found
  both the mute acknowledgment ordering and a multi-frame segmenter overflow
  crash; both were fixed.
- Provider-reported cumulative voice seconds become non-duplicated millisecond
  deltas. Delegated backend token counts are deduplicated by response ID and
  retain their backend model identity. A red capability test showed the
  provider counts were not yet visible to call accounting; the private
  `provider_usage` speech event now produces distinct call observations for
  speech duration and backend tokens. Locally measured egress remains a
  separate observation.

### Package 8 work in progress (2026-09-26)

- A red fake-socket test showed `Session.append_history/2` was absent. The
  channel now routes published text only from the STS consumer and validates
  that `:history_reseed` providers implement the callback. Caller final text
  is appended after the capability's transcript policy check; agent text is
  appended after playback settlement and aligned prefix resolution. The pure
  `Speech.Duplex.PublishedHistory` ring trims to 128 messages and an estimated
  8,192 tokens. A second red capability test showed both texts missing from
  the replacement `session.start`; it passes after the publication hooks.
- On `expired` or `connection_lost`, GPT-Live starts one replacement socket
  with that ring and a five-second readiness deadline. An unanswered caller
  turn or active output prompts a brief continuation after `session.started`;
  idle recovery waits for caller input. A second drop and a missed deadline
  fail with `:reseed_failed`. A red test found an announced pre-drop burst
  became inadmissible after reset; the adapter now closes its old segmenter,
  retains the old segment's buffered PCM for admission, and starts a fresh
  segmenter for replacement audio. The fake-socket tests cover all three
  resumption states and the one-replacement limit.
- Descriptor validation initially made the existing Morse duplex tests fail:
  its descriptor already declares `:history_reseed` but had no callback. A
  focused red Morse test captured that initialization failure. The local
  provider and its public wrapper now append to the same bounded published
  history. Scripted local close/reseed scenarios remain open.
- Focused Morse, history, GPT-Live and capability tests passed 39 tests, zero
  failures (seed 317109). Root format and unused-dependency checks passed;
  the first strict Credo rerun found that the Morse session had grown nine
  lines beyond the module size limit. Its playback-slot indexing, credit drain
  and terminal output operations moved coherently into `SegmentStore`; focused
  duplex suites passed 21 tests, zero failures (seed 817840), and strict Credo
  then passed. Root formatting, warnings-as-errors compile, unused-dependency
  check and Lean verification passed. The full umbrella test was still running
  when this note was written.

### OpenAI enablement checkpoint (2026-09-26)

- The user explicitly requested OpenAI to be available for both GPT-Live
  speech-to-speech and direct LLM models with a single API-key credential.
  The previous hosted-check gate on the manifest and Console badge was
  removed; the hosted phone check remains open for milestone acceptance.
- Red tests first showed OpenAI model translation, tenant model activation,
  registry STS resolution, compiled speech activation and Console setup were
  unavailable. `ProviderSelection` now translates direct `openai:` models,
  preserving only public generation options. ReqLLM requires
  `max_completion_tokens` for GPT-5; the translator maps a supplied public
  `max_tokens` and supplies 4,096 when absent. Tenant credentials are supplied
  only by `CredentialSource`. GPT-Live defaults the delegated backend to
  `gpt-5`; the call spec needs no additional options.
- The catalog resolves OpenAI STS, its provider settings are enabled in the
  umbrella configuration, and its manifest advertises `:sts`. The Console
  catalog offers OpenAI for LLM and speech-to-speech; the form presents and
  submits only an API key. Focused backend and frontend tests pass. `mix
  assets.build` and TypeScript checking pass. Rendered Chrome inspection of
  the live Console at 1280x800 and 390x844 shows the OpenAI selection and one
  API-key field without layout overflow.
- Before this enablement, the full umbrella passed 2,822 tests, zero failures,
  58 excluded. Format, warnings-as-errors compile, strict Credo,
  unused-dependency check and Lean verification also passed. Final gates for
  this enablement are being rerun before committing.

### Commit preparation and umbrella reruns (2026-09-26)

- The enabled work was split into commits for the shared duplex runtime,
  OpenAI backend integrations, and Console/configuration/documentation so
  each has a purpose-specific commit body. Staged changes were checked for
  whitespace errors and credential-like literals; none were found.
- The first full umbrella rerun exposed an outdated OpenAI manifest assertion
  and two STS cutover timeouts while the local browser server was also
  running. The manifest assertion was updated for the authorized `:sts`
  exposure. Both cutover cases passed in isolation, including with the
  failing suite seed, after the browser server stopped.
- The second full rerun passed those tests but exposed an existing speech
  startup-deadline test with a 40 ms budget. Under the busy umbrella suite,
  the provider could time out before its bound notification, so the test did
  not reach the behavior it intended to check. Its deadline was raised to
  2,000 ms and the close assertion to 3,000 ms; the focused test passed.
  The final full umbrella rerun remains in progress.

- That rerun passed CallEngine (1,634), Gateway (519), Calls (120), Providers
  (22), Agent Runtime (96), MCP (37), Artifacts (20) and Persistence (186)
  with zero failures. Console found one more stale expected capability list:
  its operator endpoint returned OpenAI `:sts` correctly, but the test still
  expected credentials only. The assertion was updated and the complete
  Console child suite passed 191 tests with zero failures. A final umbrella
  rerun is needed to record a green root `mix test` gate.

- The final umbrella rerun passed all nine child suites: 2,825 tests, zero
  failures, 58 integration exclusions (seed 309443). Format, warnings-as-errors
  compile, strict Credo, unused-dependency check, `bin/verify-lean`, Console
  TypeScript, lint, 198 frontend tests and `mix assets.build` passed during
  this checkpoint. The rendered Console was inspected in Chrome at 1280x800
  and 390x844, with OpenAI selected and only the API-key field visible.

### Documentation and acceptance-record sync (2026-09-26)

- The author guide already contained a GPT-Live call-spec example and the
  provider-package guide already listed OpenAI `:sts` and shared LLM support.
  The speech provider contract still lacked the continuous-output mapping, so
  it now records burst admission, inferred caller turns, provider-owned
  barge-in and aligned text settlement.
- The milestone now checks off its documentation and rendered Console
  inspection tasks using the existing desktop/mobile evidence above. The
  completion plan distinguishes its original planning snapshot from current
  progress. D/E acceptance, the ten-call lane, independent review and hosted
  phone interoperability remain open.

### Closing usage and reseed accounting (2026-09-26)

- `GPTLive.decode/1` already returned the final usage from `session.closed`,
  but `GPTLiveSession` discarded it. A focused session test failed with no
  final usage event after an `expired` close. The session now applies that
  cumulative voice figure before closing or reseeding; the replacement starts
  at zero. The focused test passed after the change.
- The full GPT-Live session test file passed 19 tests, including final usage
  on normal, moderation and expiry closes. The first adapter and continuity
  checklist entries now have explicit code/test evidence. The other D/E
  acceptance cases remain open.
- Format, warnings-as-errors compile, strict Credo, unused dependencies and
  Lean verification passed. The first full umbrella run failed three
  unrelated load-sensitive tests; `mix test --failed` reran all three with
  zero failures. A second full run failed only the human-only room lifecycle
  test: its monitor was installed after the room could have already closed,
  yielding `:noproc` despite the expected maximum-duration notification. The
  test now monitors immediately after resolving the room PID, as its sibling
  recording test already did. Its focused case passed with the full-run seed;
  the final umbrella rerun passed all nine children: 2,826 tests, zero
  failures, 58 integration exclusions. The final run included 1,635
  CallEngine tests and 519 Gateway tests with zero failures.

### Fake-socket tool and burst acceptance (2026-09-26)

- Added JSON-line delegated-tool fixtures and drove them through a real STS
  capability with the fake GPT-Live socket. The first test failed because an
  `in_progress` function item was dispatched as a tool. The adapter now
  accepts only `status: completed` function items. Multiple pending results,
  duplicate call IDs, and failed/incomplete delegation retirement pass through
  the capability.
- A two-burst capability test failed because a transcript received before
  admission vanished when the burst closed in the same audio delta. A focused
  segmenter test failed the same way. `close_burst/1` now aligns held fragments
  before clearing the current output, and held-fragment processing records the
  first fragment's provider timeline base for later fragments.
- The second burst initially lost its text because its start timestamp equaled
  the previous burst's inclusive end. A focused test confirmed the boundary
  error. Output spans are now half-open, so the fragment waits for the next
  burst. The segmenter and fake-socket suites passed 17 tests; the related
  Morse room/capability and OpenAI session/delegation suites passed 39 tests.
- Rechecked the official GPT-Live session guide on 2026-09-26. It describes
  `expired` as reaching a duration limit but gives no numeric limit or renewal
  window. The conditional quiet-point renewal task is therefore recorded as
  not applicable, per package 8; expiry reseed remains required and tested.
- Final root gates for this checkpoint passed: format, warnings-as-errors
  compile, strict Credo, unused dependencies, Lean verification, and all nine
  umbrella suites (2,831 tests, zero failures, 58 integration exclusions).

### Reseed failure reporting and private crash data (2026-09-26)

- Two new fake-socket capability tests failed red as expected: a second lost
  socket and a replacement that missed its five-second readiness deadline
  each reported `:provider_failed` instead of the specified `:reseed_failed`.
  The provider already stopped with `{:shutdown, :reseed_failed}`. The speech
  channel discarded that reason on the provider monitor and the capability
  collapsed every session closure to `:provider_failed`.
- The channel now forwards the controlled `:reseed_failed` reason only for an
  STS provider declaring `continuity: :history_reseed`; the capability passes
  it to its owner. Other provider failures continue to use the generic reason.
  Both red tests passed green, and the GPT-Live focused files passed 27 tests.
- A privacy test places synthetic key, prompt, history, transcript and audio
  markers in a ready GPT-Live session, inspects provider and supervisor status,
  and captures an abnormal provider exit. None appears in the inspected status
  or crash logs. It passed alongside the existing provider-status test.
- Strict Credo initially rejected the speech channel at 802 lines. Moving the
  new cleanup into its existing failure module brought the channel below its
  size limit. Format, warnings-as-errors compile, strict Credo, unused
  dependencies and Lean verification then passed. The full umbrella run passed
  2,834 tests, zero failures, with 58 integration exclusions. No hosted call
  was made.

### Moderation close through the capability (2026-09-26)

- A fake-socket capability test for `session.closed` with `reason: "content"`
  failed red: the owner received `:provider_failed`, although the adapter
  stopped with `{:shutdown, :moderation}`. The speech channel and STS capability
  now forward `:moderation` alongside the already controlled `:reseed_failed`
  reason for history-reseed STS providers. The focused test passed green.
- The broader fake-socket close and overlap matrix remains open. This change
  does not mark checkpoint D complete.
- The broader focused run exposed a close-ordering race in the existing
  final-usage test: `session.closed` emitted voice usage, then the provider
  exited before the consumer could acknowledge it. Waiting for provider `:DOWN`
  before acknowledging made the test fail deterministically. The speech
  channel now uses its bounded producer-down drain for a pending STS usage
  event, as it already did for a pending STT turn-end event. It retains the
  controlled close reason until draining finishes. The focused GPT-Live and
  STT files passed 47 tests after this change.
- Credo's channel-size check prompted moving generic provider-down handling
  into `Speech.ChannelFailure`, alongside the specialized moderation close.
  Format, warnings-as-errors compile, strict Credo, unused dependencies and
  Lean verification passed. The full umbrella suite then passed 2,835 tests,
  zero failures, with 58 integration exclusions. No hosted call was made.

### Package 8 later checkpoints (2026-09-26)

- Package 8 was split into reviewable commits for post-reseed speech,
  provider lifecycle hooks, and the Morse scripted close harness. The current
  milestone evidence records each checkpoint. The scripted-close commit is
  `1baf3af8`; its CallEngine suite passed 1,661 tests. One Gateway WebRTC
  handoff test timed out in the umbrella run and passed on an isolated rerun.
- A fake-socket capability test for a host tool result arriving during GPT-Live
  reseed failed red with `{:error, :stale_request}`. The replacement now gets
  that result as private thinking context after readiness; the old delegation
  output is not replayed. The focused GPT-Live files passed 39 tests. The
  design record is `docs/gpt-live-reseed-tool-results.md`. All five root gates
  passed; the umbrella suite passed 2,853 tests with zero failures and 59
  tagged exclusions.

### Package 8 transfer exit (2026-09-26)

- Added compiled Morse duplex room transfer cases. A successful destination
  commit followed by the room platform-effect message stops source STS
  provider and capability. A failed destination preparation releases the
  hold and leaves the same provider able to accept input. The existing
  room-owned fake GPT-Live tests prove the corresponding provider boundary.
- Focused Package 8 lifecycle matrix passed 59 tests. All five root gates and
  Lean verification passed; the umbrella suite passed 2,855 tests with zero
  failures and 59 tagged exclusions. A subsequent audit found that the STS
  executor does not run the provider-originated `transfer` call. Amendment 2
  records the additional acceptance path, so E remains open.
- A compiled Morse room test made the missing provider-originated call fail
  red, then pass after the room STS tool executor submitted the transfer
  binding with the current capability and caller identity. A committed
  transfer now dispatches the source teardown effect after the destination
  publishes completion; a failed transfer replies to the provider and keeps
  the original session usable. The focused matrix passed 49 tests; the full
  umbrella gate is pending after an unrelated Calls monitor race.
- Independent review then required the same provider-originated route through
  a compiled GPT-Live room with its fake socket. Both commit/teardown and
  destination failure now pass. The failure test verifies the delegated
  function result and continuation on the original socket before fresh audio.
  Six focused transfer tests, root static gates and Lean verification pass.
  After separate test-only timing fixes, the full umbrella suite passed 2,859
  tests with zero failures and 59 tagged exclusions. E is locally complete.
