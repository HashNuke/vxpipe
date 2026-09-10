# Opening audio and call lifecycle

## 2026-09-10 — source schema checkpoint

- Started from `milestone/opening-audio-call-lifecycle` after the remote-MCP milestone was
  merged and pushed.
- Chose a closed tagged source object: `text` carries fixed text and `file_url` carries an
  HTTPS URL. Mixed sources, unknown keys/types, credential-bearing URLs, fragments, empty text,
  and oversized values fail during call-definition parsing.
- The source becomes typed data in the immutable resolved plan. Routine inspection exposes
  only its type so configured text and URL query data do not leak through ordinary logs.
- Released the additive call-definition shape as `20260910.02`; current fixtures and the
  development definition now select that version.
- Red evidence: the focused test first failed because `OpeningAudio` did not exist, then failed
  because the schema still reported `20260910.01`.
- Green evidence: from `apps/vxpipe_call_engine`,
  `mix test test/vxpipe/call_engine/call_definition/opening_audio_compiler_test.exs --seed 238092`
  passed with 2 tests and 0 failures.
- Broader affected-app evidence: Call Engine passed 232 tests with 1 integration exclusion;
  Calls passed 35 tests; Gateway passed 66 tests with 4 integration exclusions; Console passed
  56 tests. Root `mix compile --warnings-as-errors` passed, and strict Credo reported no issues
  across 368 source files and 3480 modules/functions.
- A root invocation of the focused test compiled the umbrella but could not create the test
  database because this shell lacks its PostgreSQL password. That is an environment barrier,
  not presented as passing umbrella evidence. Root formatting completed before that failure.
- Runtime fetch/format/cache policy, playback completion gating, greeting modes, and lifecycle
  clocks remain pending.

## 2026-09-10 — fixed-text playback gate

- Added one focused room test before runtime work. Its first run failed at the expected boundary:
  attaching the caller emitted no opening TTS request.
- Kept gate state and opening-request construction in the focused
  `RoomAuthority.OpeningAudio` module. `RoomAuthority` dispatches connection and TTS callbacks;
  it does not fetch, decode, cache, or own provider transport behavior.
- Selected speech processes may warm normally. A planned STT ingress starts closed, discards
  frames without buffering, and is opened once after actual output-sink completion. Text
  admission reports retryable `opening_audio_in_progress` during the same interval.
- TTS provider completion, audio enqueue, playback start, and playback progress do not open the
  gate. A configured opening failure stops the room with `opening_audio_unavailable`.
- Unsupported file playback and fixed text without a resolved TTS binding fail plan validation
  before the room is registered.
- Reduced routine crash-log exposure by giving `TextToSpeechRequest` a bounded inspection that
  excludes the text and output-sink fields.
- Focused evidence:
  `mix test test/vxpipe/call_engine/opening_audio_room_test.exs --seed 238092` passed with
  3 tests and 0 failures. The complete Call Engine suite passed with 234 tests and 0 failures,
  with 1 integration test excluded. Formatting and warnings-as-errors compilation passed.
- File fetching/decoding/caching, first-message behavior, and lifecycle clocks remain pending.

## 2026-09-10 — fixed-greeting history primitive

- Added an Agent Runtime session boundary for recording an already-selected assistant message
  while the session is idle. This lets an exact fixed greeting enter model conversation history
  without asking the model to regenerate it or misrepresenting it as caller input.
- The focused session test failed first because `record_assistant/3` did not exist, then passed
  with 6 tests in the file. The stored message is bounded, validated, and discardable by its
  correlation so later interruption handling can remove an interrupted greeting.

## 2026-09-10 — initial-receiver greeting modes

- Added a focused first-message coordinator under Room Authority rather than adding greeting
  policy to connection or media modules. It tracks one pending/started/completed decision for
  the initial receiver and starts only when the entry caller is attached and opening admission
  is open.
- `wait_for_input` remains silent. Fixed mode records the configured text as an assistant
  message and uses ordinary room text/TTS output. Generated mode asks the model with private
  engine provenance and uses the same output path for its response.
- The initial red run failed at the intended plan boundary because fixed and generated modes
  were still rejected as unsupported. Focused room coverage then exposed and fixed a history
  ordering race by waiting for the greeting's normal completion event before admitting the
  next caller turn.
- Focused evidence: from `apps/vxpipe_call_engine`,
  `mix test test/vxpipe/call_engine/opening_audio_room_test.exs --seed 238092` passed with
  5 tests and 0 failures.
- The first complete Call Engine run exposed two unrelated short-deadline timing failures in
  archive and legacy model-inference tests; both passed when rerun at their focused boundaries.
  A second complete Call Engine run passed with 236 tests and 0 failures, with 1 integration
  test excluded.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
  The root test command reached Persistence but could not create its database because the
  current shell still has no PostgreSQL test password; no credential value was inspected or
  logged.
- Transfer/re-entry greeting activation, file opening playback/cache, immediate hangup, and
  readiness/idle/duration clocks remain pending.
