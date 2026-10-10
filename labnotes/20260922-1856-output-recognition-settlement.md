# Output recognition settlement

- New isolated worktree/branch at `d7c3af73`; no changes to main or old Google
  worktree. Read full AGENTS, milestone index/current D tasks, linked ownership,
  format/finite-input contracts, prerequisite provider milestones and native
  Morse/Google STT plus controlled output fixtures. No teammate runner used.
- Existing Output overwrites stt_text on every segment and permits settlement
  on the first endpoint. finish_input returns acceptance without a finite-stream
  terminal signal. Failure retirement already exists; successful reuse is unsafe.
- Before tests/code: recorded concrete tasks and a focused decision/rejected
  alternatives document. Notified parent that ordered STT input_finished proof
  is needed. Use one recognizer allocation per reply, bounded finals, and existing
  deadline as failure only. No Google STS or handoff changes.
- Dependency sources copied into this worktree, excluding compiled artifacts;
  own _build, two schedulers, child-focused commands only.
- Parent review approved explicit terminal evidence and required truthful early
  admission. Before implementation added descriptor `finite_input?`/startup-gate
  design and hosted-support open task. Only local Morse and three test fixtures
  currently export finish_input; Google/Deepgram STT do not. Human STT stays
  unchanged; existing Google sidecar startup evidence must not imply terminal proof.
- Initial cold-build attempt stopped before tests because excluding ebin also
  excluded packaged `.app` manifests. Restored those source manifests only;
  no shared BEAM artifacts/build are used.

## Recorded red-green evidence

All commands below run from `apps/vxpipe_call_engine`, with
`ERL_FLAGS='+S 2:2'` and `MIX_BUILD_PATH` pointing to this worktree's own `_build`.
Output was captured by the command tool, not redirected to a filesystem log;
the session handles below identify those terminal outputs. No main build writes.

1. Cold build handle `51555` failed before tests (missing Ranch `.app` manifest);
   this is a build obstacle, **not** a behavior red.
2. Before runtime changes, handle `15059`, exit 2:
   `mix test test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs --seed 0`.
   **25 tests, 2 failures**: first `turn_ended` published `FIRST` immediately
   after playback rather than waiting for another segment/terminal proof;
   the successful ONE-to-TWO test could not emit `input_finished` because
   the original event contract rejected it as `:invalid_event`.
3. Before runtime changes, handle `45638`, exit 2:
   `mix test test/vxpipe/call_engine/capability/output_recognition_test.exs test/vxpipe/call_engine/speech/descriptor_test.exs test/vxpipe/call_engine/speech/stt_finish_input_test.exs test/vxpipe/call_engine/plan_startup/output_stt_configuration_test.exs --seed 0`.
   **18 tests, 5 failures**: missing bounded-aggregation helper (two tests),
   rejected finite-input descriptor field, absent Morse terminal event, and
   PlanStartup accepting Google sidecar selection without terminal capability.
4. First implementation run `14070`, exit 2: output-STT/accumulator/descriptor/
   finish-input files, **35 tests, 4 failures**. Existing fixtures assumed
   recognizer reuse or one final segment meant complete; migrated them to
   explicit terminal proof, fresh-session readiness and post-terminal idle loss.
5. `61785`, exit 2: added startup tests, **43 tests, 2 failures**. Human Google
   fixtures needed the existing required `media_ingress` host setting; added it
   to test settings only. No startup implementation relaxation.
6. `71119`, exit 0: same five files after adding missing-terminal deadline and
   conflicting/oversized aggregate coverage, **46 tests, 0 failures**.
   Only then extracted recognizer lifecycle code to satisfy Output's 800-line
   limit; recorded this ownership review in the milestone before refactoring.
7. `14331`, exit 2: expanded owning-child regression set, **138 tests, 1 failure**.
   Added Deepgram admission fixture omitted required encoding and used the wrong
   public model; corrected to `flux-general-en`/`linear16`, not a runtime change.
8. `61306`, exit 0: **139 tests, 0 failures**. No live command after completion.
   Exact regression command:

```shell
mix test test/vxpipe/call_engine/speech/descriptor_test.exs test/vxpipe/call_engine/speech/event_contract_test.exs test/vxpipe/call_engine/speech/stt_finish_input_test.exs test/vxpipe/call_engine/speech/provider_contract_test.exs test/vxpipe/call_engine/capability/speech_to_speech_test.exs test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs test/vxpipe/call_engine/capability/output_recognition_test.exs test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs test/vxpipe/call_engine/plan_startup --seed 0
```

Hosted finite-input proof remains unimplemented and explicitly open. Google and
Deepgram ordinary human STT retain their existing descriptors/configuration;
only agent-output selection requires the new capability. Google synthetic
credentials still reach actual ordinary STT fake-wire setup and remain redacted.
No Google STS source, Channel/Session, handoff, Gateway, native or load edits.

## Final checkpoint

- Added a finite-sidecar host-disable regression and cumulative-interim inputs.
  Handle `81543` completed exit 2, **140 tests/1 failure**: the new assertion
  incorrectly assumed construction preserved the validation error path.
  Source inspection confirms existing `speech_to_speech_runtime` wraps nested
  construction errors at `speech_to_speech`, while validation reports
  `output_speech_to_text`. Test preserves both; no production change for this.
- Final handle `57427` completed exit 0, **140 tests, 0 failures**, seed 0,
  5.3 seconds, using the exact expanded command above and the same isolated
  two-scheduler environment. No command remains live.
- `mix format --check-formatted` on the exact changed Elixir files and
  `git diff --check` both exited 0. Output is now 750 lines (below the existing
  800-line gate). Inspected implementation, tests and docs diffs before staging.
- No root/static umbrella, native, load or hosted gates were run for this
  checkpoint; parent owns serial integration acceptance. Milestone/index remain
  unchecked. No dependency/manifest/UI enablement or hosted terminal support.

Exact checkpoint paths (all relative to this worktree):

- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability/speech_to_speech/output.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability/speech_to_speech/output_recognition.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability/speech_to_speech/output_recognizer.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup/output_stt_format.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/provider/morse_code_stt/session.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/descriptor.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/event.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech/stt_provider.ex`
- `apps/vxpipe_call_engine/test/support/speech_output_stt_failing_provider.ex`
- `apps/vxpipe_call_engine/test/support/speech_output_stt_slow_provider.ex`
- `apps/vxpipe_call_engine/test/support/speech_output_stt_stalling_provider.ex`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/capability/output_recognition_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/plan_startup/output_stt_configuration_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/descriptor_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/event_contract_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/stt_finish_input_test.exs`
- `docs/google-speech-integration.md`
- `labnotes/milestones/agent-speech-to-speech.md`
- `docs/output-recognition-settlement.md`
- `docs/speech-integration-guide.md`
- `docs/speech-provider-contract.md`
- `labnotes/20260922-1856-output-recognition-settlement.md`
