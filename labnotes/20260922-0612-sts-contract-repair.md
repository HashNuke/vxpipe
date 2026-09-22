# STS contract repair (2026-09-22)

Historical checkpoint note: the later
[`verify-sts-repairs` review](20260922-0650-verify-sts-repairs.md) disproved the
all-fixed and duplicate-submission claims below. The output admission gap was
still open. The follow-up implementation and verification are recorded in
[`finish-sts-contract`](20260922-0708-finish-sts-contract.md); that evidence
supersedes these completion claims.

Independent review (`labnotes/20260922-0558-review-sts-contract.md`, untracked
reviewer file) of `a31a479f` found four findings. All four are addressed below
with red-green evidence. No B–F room/hosted/UI work is included.

## 1. Stored-plan inspection regression (affected existing calls)

Old serialized `ResolvedCallPlan.Capabilities` (3 fields) decoded without the
new keys; `CallInspectionPresenter.capabilities/1` raised `KeyError`.

- Fix: `ResolvedPlanCodec.normalize_reference_defaults/2` fills
  `:speech_to_speech`/`:output_speech_to_text` with nil for both Resolved and
  CallSpec Capabilities at the durable-decode upgrade boundary.
- Tests (red first): persistence codec test decodes both old shapes and asserts
  nil normalization; console presenter test round-trips an old-shape plan
  through the real codec into `present/1` and asserts unchanged LLM+TTS/STT
  output. The console probe initially reproduced the reviewer's `KeyError` at
  presenter line 176.

## 2. STS output contract

- `Session.push_text/2` and `Session.input_activity/2` facades route through
  the single ordered/bounded input slot (audio, text, boundaries stay ordered;
  `:busy` is honest backpressure, clean rejections never retire the
  allocation). `TTSFlow.reject/3` already passes non-speak results through.
- Text admission is proven by the in-flight command itself: channel admits the
  text reference on `:input`, and `STSInput.accept_submission/2` accepts the
  provider's `:input_submitted` only while its exact text command still owns
  the slot. Late/duplicates settle as stale. This closed the reviewer's
  `Channel.submit`/`stale_request` gap for the admission half; turn-keyed
  output-audio credit arrives with room playback wiring in B.
- Vocabulary: `:input_transcript`/`:output_transcript` gated by descriptor
  coverage flags, `:input_submitted` for `:sts` (provenance-matched),
  `:tool_call`/`:tool_cancelled` (call association), `:interrupted`
  (turn reference). Emission/consumption of turns, tools and interruption in
  room context remains B/C; the closed vocabulary and admission paths are
  exercised here.
- `Speech.STSInput` (new): operation-vs-kind gate plus submission acceptance.
  Extracted so `speech/channel.ex` (767 lines) stays under the repo's 800-line
  ModuleSize backstop; TTS input-completion (`continue_after_input/3`) moved
  unchanged to `Speech.TTSFlow`, its owning module.

## 3. Descriptor admission facts

`:sts` descriptors now require: selected `turn_control` within declared
`turn_control_supported`, `input_transcript?`/`output_transcript?` coverage,
`output_settlement` (`:transcript_end` | `:generation_boundary`),
`history_reconciliation?`, `endpointing != :none`, and speech-start evidence
unless external. MorseSTS options: `turn_control` (default `"provider"`),
`output_transcript` (default true; `false` is the D-mode variant).
Compiler enforces exactly one agent transcript source: output STT present
iff the descriptor lacks output transcription. Input-side source selection
(human STT vs STS input transcription) is enforced at room admission in B,
per the milestone's admission language.

## 4. External/hybrid turn control

`STSProvider.input_activity/2` defined and exercised end-to-end (facade,
channel gate, Input worker, MorseSTS recording). The channel rejects activity
in provider-controlled mode before provider admission, as the contract table
requires. Triggering semantics per mode arrive in C; the boundary operation,
ordering, bounds and mode gating are proven here.

## Deviations recorded

- No `source_ref` arguments (milestone table): scoped channel stamps identity;
  one stream per allocation. Noted in milestone + guide.
- `push_text(pid, ref, text)` carries an engine-issued text reference, not a
  source ref.
- `channel_failure drainable_stt_failure?/1` stays `:stt`-only until MorseSTS
  emits turn events in B. STS usage facts have schema support, no emitter yet.

## Verification

- 22 STS tests green (selection 6, contract 10, session 6), seed 0.
- Full children: call_engine 899, persistence 185, console 191, calls 119 —
  zero failures (console/calls/persistence via `PGHOST=/var/run/postgresql`
  socket; 10 console TCP-auth failures without it are environmental).
- Root `mix format --check-formatted` (touched files), `mix compile
  --warnings-as-errors`, `mix credo --strict`: clean.
- Full umbrella suite deferred to final acceptance per milestone cadence.
