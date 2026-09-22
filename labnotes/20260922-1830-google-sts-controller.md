# Google STS controller

- Begin at committed runtime `f9db3319` (documentation HEAD `ddcba77a`). Root
  umbrella session is still running; no runtime/build edits will overlap it.
  Previous goal turn committed transcript, codec, handoff and PCM admission
  checkpoints with focused tests; all four static gates pass.
- Source inspection: raw activity end is ignored; model `turnComplete` emits
  caller `turn_ended` and thereby admits output too late. Output text before
  capability admission is dropped; pre-admission audio reaches its 16-item bound.
  Existing adapter tests manually admit output and use model completion as caller
  end, so their green results do not establish controller ordering.
- Recorded concrete tasks and dependency review in the milestone before tests
  or implementation. Keep the raw codec, provider state/correlation and engine
  admission/playback responsibilities separate. Do not grow buffers or fabricate
  caller boundaries from text/model output to make tests pass.
- Further inspection finds one mutable `input_turn` also names response text,
  tools and interruption. Overlap/late-evidence isolation must remain an explicit
  follow-up, not be implied by sequential streaming acceptance.
- Re-read the official Live API reference: server generation/model-turn boundaries
  are distinct; final output transcription precedes generation completion, while
  input transcription has no guaranteed cross-message ordering. Client activity
  controls require disabled server activity detection. Google hybrid is currently
  advertised with automatic detection enabled and needs proof or rejection.
- Google's ADK receive implementation accumulates output transcription fragments
  before final settlement; the current adapter replaces each prior fragment.
  Verify bounded assembly and early retention at the provider boundary, preserving
  cumulative snapshots in the shared provider contract.

Primary sources inspected 2026-09-22:

- [Live WebSocket reference](https://ai.google.dev/api/live)
- [Live capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
- [Google ADK receive implementation](https://github.com/google/adk-python/blob/main/src/google/adk/models/gemini_llm_connection.py)

No hosted call or Google advertisement is authorized. A successful local fake-wire
sequential response will not close overlap, input-finalization, history or hosted
acceptance. The new controller work is not part of the running umbrella baseline.

## Initial red evidence

- Added eight actual-capability/fake-wire/sink cases after recording the tasks.
  Against unchanged compiled `f9db3319`, all eight fail: caller end never admits
  streaming output, model completion fabricates caller end, duplicate onset
  replaces its reference, and accumulated text has no bound. Text retention and
  source-isolation assertions initially stop at the missing admission boundary.
- Ran from Call Engine in a separate non-Mix VM while the root run continued in
  Gateway; no compilation or runtime changes overlapped its committed baseline:

  ```sh
  ERL_FLAGS='+S 2:2' elixir -pa '../../_build/test/lib/*/ebin' -e '
    Application.put_all_env(Config.Reader.read!("../../config/config.exs", env: :test))
    {:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
    Code.require_file("test/test_helper.exs")
    ExUnit.configure(seed: 0)
    Code.require_file("test/vxpipe/call_engine/capability/google_sts_controller_test.exs")'
  ```

- Root runtime-integration run is now terminal with the separately tracked
  Gateway transfer-active timeout. Implementation may start without altering
  its baseline. The native agent owns the controlled attachment reproduction.
- Recorded model-text source contamination before its regression: only configured
  `outputTranscription` may supply spoken text, not ordinary model text/thoughts.
  Pinned the primary ADK fragment-accumulation evidence to
  `8164341ec5dc7d21d405e553c51cb0bd41cc7afa`.
- Admission-only repair leaves six of eight checks red, now exposing actual
  early-text loss, fragment replacement, aggregate overflow and model-text
  contamination. Bounded provider assembly/source isolation makes all eight
  pass. The boundary carries the existing empty-string no-final-text convention;
  `turn_ended` requires a string, not nil. No shared event contract was broadened.
- Existing adapter fixtures have six failures because they still use model
  completion as caller completion. Migrate their wire boundary and retain their
  original buffer/fence/playback assertions; do not claim them as new controller
  proof. Before further implementation, added a task for the newly exposed
  reconnection risk: earlier local playback must not imply model-turn completion.

## Focused implementation and review

- Added the resumption regression first: nine checks, one failure; the socket
  was already retired (`wire: nil`) after local playback plus handle/go-away,
  although model `turnComplete` had not arrived. Separate model-completion state
  now guards idle resumption; completion invalidates the older handle, and only
  a later valid handle can start replacement setup. No deadlines were enlarged.
- Updated six old fixture cases to use raw caller end, preserving their audio
  bounds, fences and no-replay assertions. Two combined-message fixtures also
  needed acknowledgements in the decoder's actual activity-before-text order;
  waiting for the second event without acknowledging the first was a fixture
  error, not a runtime delivery defect.
- Independent xhigh source review found no additional new defect in the initial
  controller/assembly diff, excluding the then-active resumption audit. Added
  its requested real-controller local/pre-admission interruption cases: retained
  OLD and fenced LATE text cannot enter the fresh NEW reply; no old successful
  completion is published. This is local isolation, not history reconciliation.
- Focused owning-child group is green: **65 tests, zero failures**, seed 0,
  `ERL_FLAGS='+S 2:2'`, using:

  ```sh
  mix test test/vxpipe/providers/google/sts_test.exs \
    test/vxpipe/providers/google/sts_session_test.exs \
    test/vxpipe/providers/google/sts_output_test.exs \
    test/vxpipe/call_engine/capability/google_sts_controller_test.exs \
    test/vxpipe/call_engine/capability/sts_transcript_settlement_test.exs --seed 0
  ```

- Provider contract and Google integration documentation are synchronized. The
  parent controller task remains open: independent overlap correlation, delayed
  caller-final publication, external/hybrid claims and interrupted model history
  are not closed by sequential streaming tests. Google remains unadvertised.
- Independent guard review identified a further P2: after A playback, B can
  start before A's model end; that delayed end makes the scalar completion flag
  falsely certify B idle after B playback. Recorded the reproduction and a
  conservative ambiguity latch before its red. This is interim resumption
  safety, not completion or rejection of the milestone's overlap requirement.
- The exact P2 reproduces in all three real controller paths: 14 tests, three
  failures, each showing that the old wire was retired prematurely. Added a
  private allocation-lifetime ambiguity latch on new logical provider/typed/
  external starts before the previous model end. Later ends/handles cannot clear
  it. The tests verify explicit failure without replacement on connection loss.
- The expanded group now passes **68 tests, zero failures** with the same command
  and seed. Retained-text interruption cases also pass. The ambiguity guard is
  deliberately documented as an interim safety limit, not finished overlap
  support or permission to advertise Google STS.
- Independent xhigh rereview clears the P2 repair within that conservative scope:
  the latch is monotonic across all three logical starts and cannot be cleared by
  completion, settlement, fencing or new handles. Both text-fence cases meet the
  requested coverage. Reviewer performed source review only; the parent reran
  all 68 checks after the repair, with zero failures and no test compile warnings.
- The checkpoint will be committed before broad root gates. The preceding
  umbrella failure remains independently tracked in the native handoff work;
  it cannot be reported as a clean root pass for this Google change.
