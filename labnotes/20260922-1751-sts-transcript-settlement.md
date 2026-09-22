# STS transcript settlement

- Preparing the existing explicit-final milestone task while the sidecar umbrella
  runs on its committed runtime. Added the detailed behavior/verification tasks
  before tests or implementation. The umbrella Call Engine lane had already
  completed (1,144 tests); new focused tests below are not part of that baseline.
- Baseline inspection: Event rejects `final` for output transcripts; Morse declares
  transcript-end settlement but omits the marker; capability accepts any latest
  text and Output treats provider text as ready regardless of the descriptor.
- Plan: snapshot/final validation, selected settlement mode, matching playback,
  one bounded post-generation deadline, stale/final immutability, and preserving
  the independently selected output-STT path. History reconciliation remains
  separately open; no Google wire or provider enablement changes belong here.

## Focused red

- Pure event red: two checks, one expected failure because `final: false` (and
  therefore the intended explicit-final vocabulary) is rejected.
- Nine event/capability checks against the unchanged committed runtime: eight
  expected failures, seed 0. Observed partial text published after playback,
  post-generation text replacing the boundary snapshot, no explicit-final timer,
  no missing-generation-text failure, and rejected explicit final events.
- Added budget validation: ten tests, nine expected failures; invalid `nil`
  budget currently starts successfully. The real Morse conversation check also
  fails because its advertised explicit-final transcript has `final: nil`.
- Ran the new tests in a separate non-Mix VM using the existing test BEAMs and
  compiling only the modified contract-provider fixture in memory. Main runtime
  sources/build remain unchanged while the umbrella finishes. These reds are not
  part of that umbrella's already completed Call Engine lane.

Reproduction from the Call Engine child (after ordinary test compilation exists):

```sh
ERL_FLAGS='+S 2:2' elixir -pa '../../_build/test/lib/*/ebin' -e '
Application.put_all_env(Config.Reader.read!("../../config/config.exs", env: :test))
{:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
Code.compiler_options(ignore_module_conflict: true)
Code.require_file("test/support/speech_sts_contract_provider.ex")
Code.require_file("test/test_helper.exs")
ExUnit.configure(seed: 0)
Code.require_file("test/vxpipe/call_engine/speech/sts_transcript_final_test.exs")
Code.require_file("test/vxpipe/call_engine/capability/sts_transcript_settlement_test.exs")'
```

## Implementation and focused green

- Began runtime edits only after sidecar umbrella exited 0 (2,304 tests). Added
  the boolean output-final vocabulary and made Morse emit its promised final.
- OutputTranscript owns provider-snapshot settlement without a new process:
  explicit finals freeze once; generation boundaries freeze the prior snapshot
  or fail missing text. Output still owns sink/credit/sidecar settlement.
- One validated 1–30,000 ms deadline (default 5,000) starts after generation
  acknowledgement for missing explicit finals. Partial updates cannot renew it.
  Final receipt/fencing cancels it and a fresh output reference isolates stale
  timer delivery. Invalid budgets reject startup before speech allocation.
- First green: eleven new/strengthened tests passed. Added cancellation while
  playback remains pending and stale text/timeout across hold/replacement checks;
  the resulting combined event/Morse/capability/room group passes **132 tests,
  zero failures**, seed 0. Existing 119 capability/room checks pass unchanged.
- Normative contract, author guide and output-admission decision synchronized.
  History reconciliation remains an explicit open task; no Google wire, provider
  manifest, hosted calls, playback guarantees or transcript fallback changed.

## Deadline review repair

- Source review identified that synchronous sink finalization could consume time
  before the transcript timer began. Recorded the task before adding a deferred
  sink regression: hold its finish reply past a 25 ms budget, queue a final, then
  release the sink. The capability accepted that late final: eleven capability
  tests, one expected failure, seed 0.
- Moved generation acknowledgement and deadline creation before sink finalization.
  Retain absolute monotonic expiry and check it after sink finalization and before
  accepting text. The deferred sink cannot restart or extend the budget.
- Independent source review otherwise found final immutability, generation-boundary
  freezing, matching playback, hold cancellation and output-STT separation sound.
  Qualified the contract's text-required completion rule to provider-transcript
  mode: output-STT retains its explicit failure/no-text completion behavior.
  Limited retirement claims to different turns and fresh timeout references;
  full upstream retirement/history reconciliation remain open.
- Final focused run after the absolute-deadline repair: **133 tests, zero
  failures**, seed 0. The expected redacted capability shutdown log belongs to
  existing failure coverage. No umbrella result is claimed for this new runtime
  until the post-commit integration gates run.
- Independent xhigh source rereview cleared the deadline repair with no additional
  correctness finding. The budget bounds final acceptance, not instantaneous
  shutdown: an in-flight synchronous sink call can delay failure handling within
  its existing 15-second bound. Recorded that distinction in the contract.
- Exact-file format and diff checks pass. Commit this checkpoint before the
  broader integrated umbrella gates, per the requested workflow.

```sh
# From apps/vxpipe_call_engine
ERL_FLAGS='+S 2:2' mix test \
  test/vxpipe/call_engine/speech/sts_transcript_final_test.exs \
  test/vxpipe/call_engine/capability/sts_transcript_settlement_test.exs \
  test/vxpipe/call_engine/speech/morse_sts_conversation_test.exs \
  test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs \
  test/vxpipe/call_engine/capability/speech_to_speech_test.exs \
  test/vxpipe/call_engine/room_authority/speech_to_speech_test.exs \
  test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs \
  test/vxpipe/call_engine/room_authority/sts_output_identity_test.exs \
  test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs --seed 0
```
