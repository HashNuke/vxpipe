# Output STT private configuration

- Started from clean `dd501d39` in the same isolated worktree. Main checkout and
  build are outside this task; all BEAM commands use this checkout's build and
  two schedulers. Parent explicitly authorized this bounded native checkpoint.
- Read the milestone/index and existing STT resolution, room allocation and
  sidecar private-init contracts. Added finer subtasks before tests or code.
- Baseline: output-STT adapter/options validation accepts Morse only; PlanStartup
  discards the private result from SpeechToTextRuntime; room allocation passes
  an empty sidecar-private list. Separate PrivateInit plumbing already exists
  through RoomCapabilitySupervisor and the STS tree into Output.start_output_stt.
- Scope excludes capability/Output/Usage, Session/Channel, Google STS and PCM
  negotiation. Use matching 16 kHz Morse/Google fixtures for startup proof only.

## Red-green sequence

- Initial fixture explicitly supplied JSON `encoding: "linear16"`; ordinary Google
  STT already rejects that option representation. Removed the explicit encoding
  and used the existing default; no unrelated encoding change was made.
- Corrected focused run: 2 tests, 2 expected failures. Catalog adapter returned
  `:unsupported_capability` for Google output STT; the real CallSpec rejected the
  output slot. Delegating output-role catalog operations to ordinary STT made
  selection pass and exposed the missing private runtime field (2 tests, 1 failure).
- Retaining the SpeechToTextRuntime private result made startup green. Added the
  real room allocation test before changing the room helper: 3 tests, 1 expected
  failure; no fake-wire start arrived, because room allocation still passed an
  empty private list. Forwarding the dedicated field made all 3 pass.
- Added admission regressions: missing/disabled host, missing/wrong-tenant
  credentials, invalid provider/model/rate and public credential/module injection.
  Five focused tests pass. Google STS registry capability remains unavailable.
- Review repair interrupted this checkpoint and was committed separately as
  `2bd28042`; sidecar changes remained unstaged throughout that commit.

## Decisions and verification

The public provider tuple is unchanged. A dedicated inspection-excluded private
field preserves credential/config/transport options without mixing them with
the generator's private activation. Existing RoomCapabilitySupervisor/STS tree
PrivateInit ownership supplies the sidecar; no shared speech internals changed.
The room test verifies the actual Google session and setup, synthetic API-key
header, redacted process status, no audio submission, and owner cleanup.

Run from `apps/vxpipe_call_engine` in the isolated checkout. Set `MIX_BUILD_PATH`
to that checkout's own `_build` absolute path; all runs use `ERL_FLAGS='+S 2:2'`.
The successive red/green command was:

```sh
mix test test/vxpipe/call_engine/plan_startup/output_stt_configuration_test.exs --seed 0
```

Compatibility run (95 tests, 0 failures, seed 0; 6.1 seconds):

```sh
mix test test/vxpipe/call_engine/plan_startup \
  test/vxpipe/call_engine/call_spec/sts_selection_test.exs \
  test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs \
  test/vxpipe/providers/google/stt_test.exs \
  test/vxpipe/providers/google/stt_session_test.exs \
  test/vxpipe/providers/google/sts_test.exs \
  test/vxpipe/providers/google/sts_session_test.exs --seed 0
```

Existing room transcript-mode tests were run unchanged. The suite includes an
expected sanitized capability termination log (`:redacted`), not a test failure.
Scoped formatting and `git diff --check` pass. No full umbrella/native/load gates
ran here; parent owns them. No hosted calls, credential inspection, manifest/UI
enablement, PCM conversion or finalization acceptance is claimed. The overall
adapter/config/PCM milestone item stays unchecked pending format handling.
