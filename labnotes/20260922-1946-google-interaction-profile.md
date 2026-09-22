# Google interaction profile

- Research starts at committed runtime `6104eda1`, documentation `c091a3ac`,
  while root test handle `57918` is live. Main runtime and compiled artifacts
  remain unchanged; the previous goal turn made concrete committed progress.
- Pinned ADK `8164341ec5dc7d21d405e553c51cb0bd41cc7afa` sends a new single-part
  Gemini 3.x text request via `send_realtime_input(text=...)`; current STS encoder
  still uses client history content. Correcting this is a new-input operation,
  not history reconstruction, replay or a placeholder request.
- The same receiver surfaces interaction status alongside model turn completion
  because one prompt can produce several model turns. Pinned Python SDK
  `938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab` defines `IDLE`, `IN_PROGRESS`,
  unspecified and deprecated `REQUIRES_ACTION`; the latter is not evidence to
  silently equate with completed background work. REST documents this status
  alongside `turnComplete`. Current codec ignores it and session treats every
  model end as potentially idle.
- Added concrete tasks before implementation: exact typed wire/controller proof,
  validated interaction-idle evidence for renewal, and successful subsequent
  response generation after an in-progress model end. An idle guard alone does
  not complete multi-model-turn response ownership. No hosted call is authorized.
- Initial red: independent VM command handle `20011`, exit 2, **58 tests, eight
  failures**, seed 0, two schedulers. Exact typed envelopes remain client history;
  codec ignores interaction status/invalid enums; missing, unspecified, deprecated
  action-required and in-progress model ends all permit premature wire retirement.
  New tests were added only after root `57918` completed its Call Engine lane
  (1,233 tests, zero failures). The red VM loads unchanged test BEAMs and invokes
  no Mix task, preserving attribution of the continuing root baseline.

  ```sh
  elixir -pa '../../_build/test/lib/*/ebin' -e '
  Application.put_all_env(Config.Reader.read!("../../config/config.exs", env: :test))
  {:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
  Code.require_file("test/test_helper.exs")
  ExUnit.configure(seed: 0)
  Code.require_file("test/vxpipe/providers/google/sts_test.exs")
  Code.require_file("test/vxpipe/call_engine/capability/google_sts_controller_test.exs")'
  ```

  Execute from Call Engine with `ERL_FLAGS='+S 2:2'`. This is behavior red,
  not a source-only inference or an umbrella failure.
- Expanded red: handle `10918` exited 2, **59 tests, nine failures**; log
  `vxpipe-google-interaction-profile-tool-red.log`. The extra actual-controller
  reproduction submits a tool result after reply playback and explicit model
  idle, then supplies a newer handle/go-away. Current code retires the wire
  before any post-result model/idle evidence. Added the task and separate design
  review before this test. The main runtime/build are still unchanged.
- The prior user-status turn was read-only, not implementation progress. This
  continuation revalidated root handle `57918` as live, added the stronger red
  and documented the profile decision in `docs/google-sts-controller.md`.
  Sent the requested CLI progress notification successfully. No fresh root run,
  hosted request or native/load acceptance has been started.
- Root `57918` subsequently completed successfully: its result is recorded in
  `labnotes/20260922-1941-google-caller-renewal.md` and commit `ccb8f5ee` before
  runtime edits. Implemented exact new realtime text, validated completion/status
  tuples, separate interaction-idle renewal evidence, and invalidation at genuine
  caller end/new input/tool-result submission. Initial no-work setup retains
  safe-handle renewal. No existing timer budget or ambiguity latch was relaxed.
- First focused implementation run `44963` exited 2: 85 tests, six fixture
  failures. The nine new behavior regressions passed; remaining old fixtures
  omitted explicit idle or expected the old unqualified codec event. Updated
  genuine idle fixtures and retained missing-status coverage. Also changed
  existing overlapping-model/late-caller fixtures to explicit idle, so they still
  test their original fences instead of passing only because status is missing.
- Focused green `10010` exited 0: **85 tests, zero failures**, seed 0, two
  schedulers. Log `vxpipe-google-interaction-profile-green.log`. Command from
  Call Engine, with `ERL_FLAGS='+S 2:2'`:

  ```sh
  mix test test/vxpipe/providers/google/sts_test.exs test/vxpipe/providers/google/sts_session_test.exs test/vxpipe/providers/google/sts_output_test.exs test/vxpipe/call_engine/capability/google_sts_controller_test.exs --seed 0
  ```

  Broader recognition/startup/real-room regression and independent source review
  are in progress. Successful subsequent response delivery is still a separate
  implementation task, not completed by this guard.
- The first integrated regression handle `56268` exited 0: **238 tests, zero
  failures**. Independent Astra xhigh review then identified pre-onset PCM and
  unowned model activity retaining old idle, and requested a no-op false
  completion boolean. The previous generic flag decoder already rejected false;
  this is a protocol-profile improvement, not a new regression introduced here.
  The reviewer also requested explicit idle in ambiguity fixtures; that stronger
  fixture change was already included before the report.
- Recorded all review tasks before tests/code. Red `36723` exited 2: **66 tests,
  seven expected failures**, log `vxpipe-google-interaction-review-red.log`.
  Two actual-controller cases send PCM after pristine or settled idle, then a
  handle/go-away before caller onset. Three cases send fresh audio, thought-only
  model content or output transcription after settled idle. All five prematurely
  replace the wire. Two codec reds cover false completion and private activity.
- Repair separates PCM idle invalidation from proven model activity; PCM does
  not fabricate onset or false overlapping-model ownership. Observe model parts,
  output transcription and tool calls before content ownership can discard them.
  The private activity marker carries no text and publishes nothing. Subsequent
  genuine caller completion/new idle/new handle still successfully renews.
- First repair run `58788` exited 2: 92 tests, one old large-audio fixture failure
  because it assumed every codec event was audio. Explicitly consume the new
  private activity marker while retaining exact byte/tail assertions. Then
  integrated handle `12610` exited 0: **245 tests, zero failures**, seed 0, two
  schedulers; log `vxpipe-google-interaction-review-integration.log`. Used the
  full command in `labnotes/20260922-1922-recognition-deadline-proof.md` plus
  the four Google files above. Changed Elixir files formatted successfully.
  Independent follow-up source review remains pending; no hosted acceptance.
- Follow-up review found standalone `generationComplete`/`interrupted` also
  retaining idle. Added the task, two controller reds and two same-envelope idle
  controls before code. Red `19584`, exit 2: **44 controller tests, two expected
  failures** (`vxpipe-google-model-boundary-red.log`). Extend the validated
  private activity prefix to both notifications, before their completion flags,
  so an explicit idle in the same envelope is still authoritative afterward.
- Final integrated green `31098`, exit 0: **249 tests, zero failures**, seed 0,
  two schedulers (`vxpipe-google-model-boundary-integration.log`). Same expanded
  recognition/startup/room/Google command as above. Independent xhigh source
  follow-up clears this bounded diff with no actionable findings; no independent
  test run was claimed. Main compiled/test runtime is no longer frozen because
  the earlier umbrella baseline had already terminated successfully.
- Record the separate unproven cross-direction handle-coverage requirement:
  pinned SDK `SessionResumptionConfig.transparent` requests a consumed-client-
  message index. Current adapter neither requests nor accounts for it. Research
  numbering/profile and reproduce delayed old idle plus an incompletely covering
  handle before implementing no-loss proof. Successful multi-response ownership
  likewise stays open. Neither gap authorizes history replay or new credentials.

Primary sources inspected:

- [Pinned ADK connection](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/models/gemini_llm_connection.py)
- [Pinned SDK interaction enum and server content](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/types.py)
- [Live server-content reference](https://ai.google.dev/api/live#BidiGenerateContentServerContent)
