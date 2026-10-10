# Recognition deadline proof

- Scope: Goodall P2 review repair of `b0b7d411`, in the isolated recognition
  worktree. Read AGENTS, current milestone/index and finite-input contracts;
  no main/Google/controller/native/load changes or teammate runner.
- Before tests/code, added the exact suspended-consumer reproduction and design
  review to milestone D. `input_finished` currently checks generation completion
  but not elapsed deadline; processing a queued terminal ahead of a queued timer
  can falsely succeed after expiry.
- Budget inspection: Output arms the recognition timer only after both
  generation and playback complete, while recognition remains pending. Preserve
  this start point; time waiting for playback is not covered by this budget.
  Provider-transcript settlement owns a separate generation-started budget and
  is outside this repair. Reuse the existing `text_expires_at` field, monotonic
  time and failure/retirement path; a timer notification is only a wakeup.
- Reproduction plan: stalling recognizer, 500 ms timeout, finish generation and
  playback and acknowledge a final segment. Suspend capability, queue terminal,
  wait for a test-owned timer scheduled at remaining recognition budget + 50 ms,
  then resume in `after`. Require timeout, failed usage, no transcript and old
  recognizer retirement. No production sleeps or inferred quiet-period finality.
- Hosted finite-input support remains explicitly open. All BEAM commands use
  `ERL_FLAGS='+S 2:2'` and this worktree's own `_build`, from the Call Engine child.

## Red before implementation

`mix test test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs --only recognition_deadline_race --seed 0`
completed in handle `46544`, exit 2: **1 test, 1 expected failure (28 excluded)**.
The actual recognition usage outcome was `:succeeded` instead of `:failed` after
absolute expiry. Output captured in `vxpipe-recognition-deadline-red.log`
using `set -o pipefail` and `tee`; this is behavioral red, not a build failure.
Log names below are portable basenames; the original temporary directory is
omitted from the committed reproduction commands.

## Focused green

The same command after the scoped Output repair completed in handle `47874`,
exit 0: **1 test, 0 failures (28 excluded)**. Log:
`vxpipe-recognition-deadline-green.log`. The expired terminal now follows the
existing failure/retirement path; its later timeout notification is inert, with
one completed turn and one usage batch. Added assertions to the existing successful
pre-playback-final test that the recognition timer/absolute expiry remain unarmed
while playback is pending, preserving the original budget start.

## Regression and handoff

Handle `67910` completed exit 0: **152 tests, 0 failures**, seed 0, 5.5 seconds.
This includes the original 140-test recognition/startup/private/PCM/room group,
the new deadline race and 11 provider-transcript settlement checks. The latter
deadline remains independent and unchanged. Exact command from the owning child:

```shell
export ERL_FLAGS='+S 2:2'
export MIX_BUILD_PATH="$PWD/../../_build"
set -o pipefail
mix test test/vxpipe/call_engine/speech/descriptor_test.exs test/vxpipe/call_engine/speech/event_contract_test.exs test/vxpipe/call_engine/speech/stt_finish_input_test.exs test/vxpipe/call_engine/speech/provider_contract_test.exs test/vxpipe/call_engine/capability/speech_to_speech_test.exs test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs test/vxpipe/call_engine/capability/output_recognition_test.exs test/vxpipe/call_engine/capability/sts_transcript_settlement_test.exs test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs test/vxpipe/call_engine/plan_startup --seed 0 | tee vxpipe-recognition-deadline-regression.log
```

The selected red/green commands above used the same environment and `pipefail`,
with their respective log names. `mix format --check-formatted` on the two
changed Elixir files and `git diff --check` both exit 0. No commands remain live.
Staged exact paths and reviewed the cached diff before the separate repair commit:

- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability/speech_to_speech/output.ex`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs`
- `labnotes/milestones/agent-speech-to-speech.md`
- `docs/output-recognition-settlement.md`
- `labnotes/20260922-1922-recognition-deadline-proof.md`

No root/native/load/hosted checks; parent owns those gates. Playback waiting time
is still outside this recognition budget, by the explicit scope requirement;
no claim of a generation-started recognizer deadline. Hosted finite-input support
and overall milestone acceptance stay open.
