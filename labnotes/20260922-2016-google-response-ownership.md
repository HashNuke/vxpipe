# Google response ownership

- Previous goal turn made concrete progress: Google interaction profile committed
  as `49213160`, static evidence `1bb80252`, 249 integrated focused tests green.
  Full root handle `80010` is revalidated live; its Call Engine lane passed 1,253
  tests before these new test sources. Main runtime/build remain frozen until
  that baseline exits. No new root/native/load/hosted request is started here.
- Read current Google caller/output/resumption state, shared descriptor/event/
  output-credit contracts and actual capability admission/queue/policy behavior.
  Current playback retirement clears `input_turn`, so a later model response is
  discarded. If the earlier output still occupies the slot, new audio can enter
  a completed generation's queue while transcript is ignored. Reproduce both
  before implementation rather than assuming the status guard handles them.
- Added concrete milestone tasks and a focused proposed architecture in
  `labnotes/20260922-2053-google-sts-response-ownership.md` before tests/code. The actual output
  reference remains engine-issued; explicit provider response evidence must not
  fabricate caller turns or bypass policy. Record successful multi-response,
  bounded retention, caller separation and queued-policy proof as requirements.
- No runtime implementation or design-approval claim yet. Parent owns Google/
  shared response semantics. Separate native Codex workers own the Socket close
  primitive and STS tool invocation lifecycle, with disjoint write sets.
- Actual-controller red: independent VM handle `25839` exited 2, **46 tests,
  two expected failures**, seed 0, two schedulers. Log
  `vxpipe-google-response-ownership-red.log`. Both new cases complete one reply,
  receive `IN_PROGRESS`, then deliver a different transcript/PCM and generation
  completion without another caller turn. One delivers after first playback;
  the other retains first playback until all second-generation content arrives.
  Both fail because no second engine-owned output starts. Existing 44 cases pass.
  Exact non-Mix command from Call Engine (unchanged compiled baseline):

  ```sh
  ERL_FLAGS='+S 2:2' elixir -pa '../../_build/test/lib/*/ebin' -e '
  Application.put_all_env(Config.Reader.read!("../../config/config.exs", env: :test))
  {:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
  Code.require_file("test/test_helper.exs")
  ExUnit.configure(seed: 0)
  Code.require_file("test/vxpipe/call_engine/capability/google_sts_controller_test.exs")'
  ```

  Tests were added only after the live root's Call Engine lane passed. This red
  does not change the runtime/build or the attribution of root `80010`.
- Independent xhigh design review identified pre-input authorization origin,
  unified queued-policy admission, response-specific discard, acknowledged-start
  grants and owner-wide resumption as prerequisites. Recorded them in the design
  and milestone before new tests/code. Runtime remains unchanged; an opaque
  response reference cannot by itself correlate old delayed wire work after
  hold/regrant. Requested a narrow API/lifecycle design resolution, not a broad
  Gateway change or another watermark audit.
- Correct the response reproductions to avoid assuming caller-end admission.
  First PCM announces speech; output transcription alone is buffered and does
  not create an empty public agent turn. Add first-response identity evidence
  for provider, external and typed input, preserving original second-response
  red logs. Tool-only model references remain independent from caller identity.
- First revised probe `56181` exited 2 (49 tests, five failures), but two failures
  were fixture assumptions: external/typed caller-end events are not forwarded
  publicly without onset association. Read the owning CallerEvents boundary and
  obtain only their existing private caller reference for the identity assertion;
  keep admission/PCM/transcript checks on actual controller output. Do not alter
  runtime publication to satisfy a fixture assumption.
- Confirmed behavior red `88242` exited 2 (49 tests, five premature-admission
  failures). Correct a constant-branch type warning by parameterizing mode and
  configured turn control together. Final red `50538` exited 2: **49 tests, five
  expected failures**, no compile warnings, 44 existing tests still pass.
  `vxpipe-google-response-first-admission-red-final.log` shows every new case
  receiving an agent output start immediately at caller/text completion, before
  any model PCM. Owning-child command: `ERL_FLAGS='+S 2:2' mix test
  test/vxpipe/call_engine/capability/google_sts_controller_test.exs --seed 0`.
  This corrects the desired first-admission contract, not the runtime; original
  two-response loss evidence remains in the earlier `25839` run.
- Follow-up design review chose atomic context-bearing input overloads plus one
  optional provider submit_input callback through the existing input slot. Gave
  the isolated tool worker that bounded shared-input assignment, with exact
  disjoint ownership; parent retains response event/grant/capability/Google work.
  No separate mutable set-context call, no silent callback fallback.
- Record the unresolved cutover trace: A accepted, A model end IN_PROGRESS, local
  hold/regrant, B reaches wire, then unlabelled model content. Neither latest
  context nor bare turnComplete proves B owns it. Pre-wire backpressure is a
  narrow safety prerequisite, not acceptance of full cross-origin lifecycle.
- Next parent RGR targets a pure bounded response-state owner before wiring the
  actual controller: separate current wire and playback records with immutable
  supplied origins, global budgets, exact retirement and all-owner quiescence.
  Added the task/design before tests/code. It grants no policy authority and
  cannot by itself prove successful controller or hosted response delivery.
- Pure owner red `5003` exited 2: **10 tests, ten expected failures** for the
  missing STSResponses module (`vxpipe-google-response-owner-red.log`). Implemented
  only this pure owner, without changing the live adapter or shared contracts.
  Green `23401` exited 0: **10 tests, zero failures**, seed 0, two schedulers
  (`vxpipe-google-response-owner-green.log`). Exact owning-child command:
  `ERL_FLAGS='+S 2:2' mix test test/vxpipe/providers/google/sts_responses_test.exs
  --seed 0`. Its shared budget counts all retained response records, not one
  allowance per reply. Settlement cannot retire an unfinished model, and an
  earlier settlement cannot make pending B quiescent. Forty sequential replies
  retire to empty bounded state with increasing ordinals.
- Requested independent xhigh review of the pure owner's source/tests before
  controller adoption. Existing actual-controller first/second-response tests
  remain red; no claim that this helper delivers speech or changes authorization.
- Broader pure-owner/provider regression `2478` exited 0: **62 tests, zero
  failures**, seed 0, two schedulers (`vxpipe-google-response-owner-regression.log`),
  covering existing Google codec/session/output plus the new owner. Independent
  xhigh source review found no concrete defect but requested three coverage
  additions before adoption: finish A credit while B still generates, discard an
  admitted response with outstanding credit, and capacity recovery/ordinal
  exhaustion. Recorded those requirements in the milestone before adding tests.
- Added six coverage cases without requiring a runtime change. The unfinished-B
  case acknowledges/completes A explicitly; it does not call the convenience
  helper's generation_end on current wire B. Admitted discard preserves its exact
  pending credit; model end before/after settlement is covered with natural wire
  ordering. Shared chunk/text/record capacity recovers without index reuse, and
  the final signed-64-bit ordinal is exhausted permanently after retirement.
- Expanded regression `6353` exited 0: **68 tests, zero failures**, including
  16 pure-owner cases, seed 0, two schedulers, no warnings; log
  `vxpipe-google-response-owner-reviewed-regression.log`. Command from Call Engine:

  ```sh
  ERL_FLAGS='+S 2:2' mix test test/vxpipe/providers/google/sts_test.exs test/vxpipe/providers/google/sts_session_test.exs test/vxpipe/providers/google/sts_output_test.exs test/vxpipe/providers/google/sts_responses_test.exs --seed 0
  ```

  Final bounded source follow-up requested. The deliberately red controller
  edits remain separate/uncommitted pending adoption; they are not claimed as
  passing evidence for this pure-state checkpoint.
- Final native Codex Astra xhigh source follow-up cleared the pure owner and
  added coverage with no findings. No independent test execution was claimed.
  Shared input delivery, channel response admission and actual Google adoption
  remain required; no cross-origin wire handoff or full milestone clearance.
- After committing the pure state owner, the next direct checkpoint begins at
  the closed semantic event shape. Add `response_started` with private reference,
  positive bounded allocation ordinal and accepted origin reference to `Event`;
  descriptor support remains opt-in. Test that exact build/support boundary red
  before code. Channel acknowledgment/high-water/grants and provider emission
  require the shared input-context integration and are separate open tasks.
- Closed event red `39956` exited 1 at test compilation because `Event` did not
  have `response_index`/`response_context` fields. Added only the strict
  `response_started` shape and descriptor support predicate. Green `12506` exited
  0: **15 shared event/provider-contract tests**, zero failures, seed 0, two
  schedulers, log `vxpipe-sts-response-event-green.log`. The event requires an
  opaque private turn reference, an origin reference and an ordinal in the
  signed-64-bit positive range. Only STS descriptors explicitly opting in can
  support it. The existing channel has not yet bound/acknowledged starts or
  authorized grants; that remains the next integration.
- Committed pure owner `9b8508b9` and response event `ec896817`, both before
  their umbrella gates. Static root handle `32426` exited 0: format,
  warnings-as-errors compile, strict Credo (1,087 source files), and unused-lock
  check pass on the committed event checkpoint. Push notification completed.
  Full root tests are pending the five deliberately red Google controller cases.
