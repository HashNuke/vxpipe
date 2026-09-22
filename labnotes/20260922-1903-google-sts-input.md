# Google STS input correlation

- Research begins at main `7c2bfb0f` / runtime `6021bc22`; main has no running
  Mix process. Native handoff verification and finite recognition implementation
  have independent agent owners. No caller-correlation runtime changes yet.
- The current Google STS codec ignores `interimInputTranscription`; the session
  emits all `inputTranscription` as partial against mutable `input_turn`, then
  erases that pointer at output settlement. CallerEvents and room CallerTurns
  retain up to sixteen associations until both activity end and final text.
  Therefore earlier output streaming is not complete caller publication support.
- Primary-source inspection changes the next action: pinned Google ADK commit
  `8164341ec5dc7d21d405e553c51cb0bd41cc7afa` handles Gemini 3.x input differently
  from the older accumulated/optional-finished branch. Its receiver treats input
  transcription as one final; the Live reference separately defines the interim
  field. Direct source inspection confirms ADK does not handle that interim
  field; do not attribute both rules to its receiver. Its model-name
  predicate includes gemini-3.8-live. Do not implement the older input profile
  merely because the shared Python Transcription type has optional `finished`.
- The Live reference still says input transcription has independent ordering.
  Keep raw activity, caller final text, model output and playback independent.
  The existing dedicated Google STT owner has a bounded pending-ended-turn queue;
  it is useful local design precedent, not proof of hosted STS correlation.
- Also recorded pinned-model typed-input and interaction-status audits before
  implementation. Upstream distinguishes new typed input from history content
  and distinguishes model end from an interaction still doing work. Do not copy
  history replay, placeholder requests or generic boundary-based input flushing.
- Added concrete unfinished milestone tasks and extended the existing controller
  decision. Next tests must prove final/end/onset permutations, more than sixteen
  completed caller turns, bounded ambiguity/failure and real-room attribution.
  Full overlap, hosted acceptance and interrupted-history proof remain open.
- Initial red at committed runtime `ebf11332`: **42 tests, seven failures**, seed
  0, two schedulers. The codec ignores interim input and lacks finality; three
  controller timing cases cannot receive provisional evidence; a final after
  playback is dropped; resumption retires the wire while a caller final is still
  pending. Test-command handle `26810` completed with exit 2. No runtime code has
  been changed. The separate VM loaded the existing test BEAMs after the running
  root suite completed its Call Engine lane; it did not invoke Mix or change
  compiled artifacts. That root run remains attributed to the committed baseline.

  ```sh
  elixir -pa '../../_build/test/lib/*/ebin' -e '
  Application.put_all_env(Config.Reader.read!("../../config/config.exs", env: :test))
  {:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
  Code.require_file("test/test_helper.exs")
  ExUnit.configure(seed: 0)
  Code.require_file("test/vxpipe/providers/google/sts_test.exs")
  Code.require_file("test/vxpipe/call_engine/capability/google_sts_controller_test.exs")'
  ```

  Run from the Call Engine child with `ERL_FLAGS='+S 2:2'`. Review is separately
  checking whether unqualified input finals justify FIFO attribution across a
  subsequent onset; the existing STT implementation is precedent, not a provider
  ordering guarantee. Do not silently treat that assumption as hosted evidence.
- Independent Astra xhigh design review rejects unproven multi-caller FIFO.
  Counterexample: A end/playback, B onset, then an unqualified final can belong to
  delayed A or final-before-end B. Bound memory is not proof of identity. Added
  concrete milestone tasks before implementation: one independent caller record,
  explicit competing-onset failure, model-interruption preservation, and pending-
  caller resumption exclusion. Typed input cannot consume an audio-final slot.
  Successful next-onset correlation remains open; no requirement is removed.
- Expanded owning-child red: handle `8472`, exit 2, **45 tests, ten failures**.
  Added actual-controller counterexamples for competing onset, typed-input
  relabelling and model interruption erasing caller evidence before implementation.
- Implemented a separate `Google.STSInput` owner with one unfinished caller record.
  Gemini 3.x interim/final codec events remain distinct; record retirement needs
  both end and final, output settlement/model interruption do not erase it, and
  typed input cannot acquire it. Competing onset fails before attribution (and
  before an external wire start); pending evidence prevents idle renewal.
- First focused run after implementation: **45 tests, seven failures**, all older
  fixtures/expectations lacking the newly required final/end facts. Updated codec
  tuple shape, provisional field and resumption/sequential fixtures. The old
  pre-admission controller case incorrectly treated model interruption as caller
  completion; it now proves no fabricated end and later explicit final/end.
  The real Session sent-ahead/pre-admission isolation test still proves a fresh
  next turn, now supplying genuine caller end/final before the model interruption.
- Expanded group: **82 tests, three failures** exposed the same missing caller
  evidence in session renewal/sent-ahead fixtures. Added those facts without
  changing production settlement/resumption rules to satisfy the old fixtures.
- Green handle `5809`, exit 0: **90 tests, zero failures**, seed 0, two schedulers.
  The real-room test deliberately injects a Google private prepared runtime before
  attaching the human; it proves owned allocation/publication and exact late-final
  public IDs, not production Google admission. No registry/manifest enablement.
  Exact owning-child command:

  ```sh
  mix test test/vxpipe/providers/google/sts_test.exs \
    test/vxpipe/providers/google/sts_session_test.exs \
    test/vxpipe/providers/google/sts_output_test.exs \
    test/vxpipe/call_engine/capability/google_sts_controller_test.exs \
    test/vxpipe/call_engine/capability/sts_transcript_settlement_test.exs \
    test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs --seed 0
  ```
- Added final immutability, unsolicited-input isolation, and external competing-
  onset rejection before a second wire start. The same group is now **93 tests,
  zero failures**, handle `41213`, exit 0, seed 0, 2.4 seconds. No runtime repair
  was needed for these three additional edge cases. Independent source review
  follows before the coherent commit and broader post-commit gates.
- Independent xhigh source review found two P2 lifecycle gaps before commit.
  The pre-admission test stopped at admission, missing that `full_fence` erased
  the provider output owner while preserving the caller. It must run through
  fresh reply playback. A related renewal guard rejects an existing external
  caller's end after model interruption, making the retained caller impossible
  to retire. Added both tasks before regression/repair; preserve caller control
  independently of model cancellation and allow existing end evidence during
  renewal rather than silently hanging an output or waiting for expiry.
- Review reproduction handle `64969`, exit 2: **28 controller tests, two expected
  failures** (fresh audio never arrives; external end returns `:busy`). Retaining
  the unfinished caller's admission anchor and allowing end evidence during
  renewal repairs both. A stronger fresh-response resumption assertion then
  fails in handle `96930`, exit 2: **28 tests, one failure** because the interrupted
  prior model end authorizes premature renewal. Recorded that task before its
  assertion; a genuine caller end now resets model completion, requiring later
  end evidence and a fresh handle before replacement. Duplicate ends remain inert.
- Full review-repair group handle `58560`, exit 0: **94 tests, zero failures**,
  seed 0, two schedulers. The pre-admission test now reaches fresh text/audio and
  acknowledged playback, and the external renewal case finishes the caller,
  settles the reply and proves safe handle handoff rather than stopping at
  admission. No hosted call or advertisement; full overlap/history still open.

Primary sources inspected 2026-09-22:

- [Pinned Google ADK receive path](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/models/gemini_llm_connection.py#L435)
- [Pinned ADK model predicate](https://github.com/google/adk-python/blob/8164341ec5dc7d21d405e553c51cb0bd41cc7afa/src/google/adk/utils/model_name_utils.py)
- [Live server-content reference](https://ai.google.dev/api/live#BidiGenerateContentServerContent)
- [Pinned SDK Transcription type](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/types.py#L2051)
