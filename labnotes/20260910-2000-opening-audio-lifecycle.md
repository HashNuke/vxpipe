# Opening audio and call lifecycle

## 2026-09-10 — source schema checkpoint

- Started from `milestone/opening-audio-call-lifecycle` after the remote-MCP milestone was
  merged and pushed.
- Chose a closed tagged source object: `text` carries fixed text and `file_url` carries an
  HTTPS URL. Mixed sources, unknown keys/types, credential-bearing URLs, fragments, empty text,
  and oversized values fail during call-definition parsing.
- The source becomes typed data in the immutable resolved plan. Routine inspection exposes
  only its type so configured text and URL query data do not leak through ordinary logs.
- Released the additive call-definition shape as `20260910.02`; fixtures and the development
  definition selected that version at this checkpoint.
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

## 2026-09-10 — platform time and hangup tools

- Released schema `20260910.03` so a participant's unified tools map can select a closed
  `platform` tool beside host and MCP entries. The initial catalog contains current UTC time and
  immediate hangup; call-definition input cannot select an arbitrary module.
- Platform tools retain the participant-local model-visible alias and default to blocking like
  every other authored tool. They execute through the same activation-owned invocation worker,
  never inline in Agent Runtime or a GenServer callback.
- The focused red run failed first at the expected parser boundary because `platform` was not a
  supported tool type. After parser/compiler support, plan startup correctly exposed its own
  unsupported-binding guard, which was then expanded for closed catalog entries.
- The first runtime attempt revealed a real cross-process race: the hangup side effect could end
  the room before its tool-start message arrived. Hangup now returns a typed worker result. The
  invocation registry sends start, completion, and effect messages in order; Room Authority
  validates the live agent/source connection and applies the effect last.
- Focused evidence: from `apps/vxpipe_call_engine`,
  `mix test test/vxpipe/call_engine/platform_tools_room_test.exs --seed 238092` passed with
  1 test and 0 failures.
- The first broader Call Engine run exposed one assertion that incorrectly expected Registry
  cleanup to be synchronous with a monitored process exit, plus an unrelated participant-test
  timing failure. The platform test now asserts the stronger owned contract—ordered start and
  completion events followed by the exact room monitor—and the unrelated test passed at its
  focused boundary. A seeded complete Call Engine rerun passed with 237 tests and 0 failures,
  with 1 integration test excluded.
- Calls passed 35 tests, Gateway passed 66 tests with 4 integration exclusions, and Console
  passed 56 tests. Root formatting, warnings-as-errors compilation, strict Credo, and unused-lock
  checks passed. Root tests remain blocked at Persistence database creation because this shell
  has no PostgreSQL test password.

## 2026-09-10 — startup readiness and maximum duration

- Added a focused `CallLifecycle` GenServer as a temporary significant child of each planned
  room incarnation. It owns timer handles and binding state; Room Authority only declares
  readiness and reacts to deadline events. Legacy ad-hoc rooms remain unchanged.
- Readiness and maximum duration begin with live room-subtree startup. The duration comes only
  from the immutable resolved plan. A lifecycle process crash shuts down the incarnation rather
  than restarting and resetting clocks.
- Entry-caller attachment marks startup ready when the plan selects no STT runtime. When it does
  select STT, readiness waits for successful capability/ingress binding. Initial fixed/generated
  greeting admission now waits for readiness as well as the opening-audio gate.
- The first two room tests failed red because no lifecycle timer existed, then passed after the
  lifecycle child and authority bridge were added. Inspection found a startup race in which a
  timer could fire before Room Authority bound to the lifecycle process. A separate focused test
  failed because the event was discarded; the process now retains and delivers unbound events in
  firing order.
- Kept the authority bridge cohesive by moving lifecycle binding and STT-dependent readiness
  decisions into `RoomAuthority.StartupReadiness` rather than adding another independent concern
  to Room Authority.
- Focused evidence: from `apps/vxpipe_call_engine`,
  `mix test test/vxpipe/call_engine/call_lifecycle_test.exs test/vxpipe/call_engine/call_lifecycle_room_test.exs --seed 238092`
  passed with 3 tests and 0 failures. The complete Call Engine suite passed with 240 tests and
  1 integration exclusion. Calls passed 35 tests, Gateway passed 66 tests with 4 integration
  exclusions, and Console passed 56 tests.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
  The root test command again stopped while creating the Persistence test database because this
  shell has no PostgreSQL password; no credential value was inspected or logged.
- Caller-idle notification, early failure on definitive provider startup failure, duration-setting
  precedence before plan compilation, and file opening playback/cache remain pending.

## 2026-09-10 — terminal STT startup failure

- Added a failing STT transport fixture and a room-boundary test for a caller whose plan selects
  STT. The red run returned `speech_to_text_unavailable` but left the readiness timer armed and
  the planned room alive.
- Added a narrow lifecycle startup-failure operation. While readiness is pending, it cancels that
  timer, records a terminal lifecycle status, and delivers the safe internal reason to Room
  Authority. Authority notifies attached connections of call-start failure and stops the entire
  attempted room subtree immediately.
- Kept legacy room behavior distinct: when no planned lifecycle exists, a failed optional STT
  attachment is detached and the room remains available. A failure after lifecycle readiness is
  likewise attachment-local rather than retroactively failing call startup.
- Focused lifecycle coverage passed with 4 tests and 0 failures. The complete Call Engine suite
  passed with 241 tests and 1 integration exclusion; Calls passed 35 tests, Gateway passed 66
  tests with 4 integration exclusions, and Console passed 56 tests.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused-lock checks passed.
  Root tests again stopped at Persistence database creation because this shell has no PostgreSQL
  password; no credential value was inspected or logged.
- Caller-idle notification, duration-setting precedence before plan compilation, and file opening
  playback/cache remain pending.
