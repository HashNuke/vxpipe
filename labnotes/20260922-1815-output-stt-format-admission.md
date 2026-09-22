# Output STT format admission

- Baseline `c4ab0c8b`, clean isolated worktree. Read startup, catalog, descriptor,
  Morse/Google configure and output-sidecar paths plus the linked format contract.
- Discovered: startup validates each provider independently but never compares
  generated STS `format` with recognizer STT `format`. STS `input_format` is a
  separate microphone format (Google 16 kHz in / 24 kHz out); using it is wrong.
- Existing Descriptor validation already owns mono/raw/linear16 or STT Opus shape,
  byte order, signedness and positive rates. There is no sidecar PCM converter.
  Choose exact validated format equality and explicit rejection before private
  credential resolution or recognizer allocation. No conversion is claimed.
- Added concrete milestone tasks/design review before tests or implementation.
  Scope: PlanStartup and dedicated pure output-STT format helper/tests/docs only.
  Parent owns capability/Output/room paths and broader gates. All focused BEAM
  commands use two schedulers and this checkout's isolated build.

## Red-green and scope evidence

- Added integration assertions before implementation: mismatched Morse 24 kHz
  output to Google/Morse 16 kHz input must fail both validation and construction.
  The red run returned `:ok` for admission. Two additional tests failed because
  the new descriptor comparison helper did not yet exist: 9 tests / 3 failures.
- Implemented the helper using existing catalog resolution/public configure and
  Descriptor.validate. Exact validated map equality requires all PCM properties;
  no private fields are read or changed. Startup checks run before activation or
  credentials; room admission already invokes PlanStartup.validate before starting
  its tree. No parent-owned room/capability files were needed.
- Focused green: 9 tests / 0 failures. Added actual CallEngine.start_call rejection
  and empty room-registry assertions; no credential-resolution or fake-wire-start
  messages occur. Existing 16 kHz Google fake-wire startup proves compatibility
  still reaches the selected recognizer with its private credential/transport.
- Real Google descriptors prove microphone input equality does not suffice:
  16 kHz microphone/recognizer inputs match, but generated 24 kHz output rejects.
  Matching 24 kHz Morse recognizer passes. Tampered descriptors exercise full
  revalidation; a valid Opus STT descriptor proves encoding mismatch rejects even
  when its rate matches. Independent 8 kHz human STT is preserved alongside the
  compatible 16 kHz agent/recognizer pair, including unchanged private config.

Commands from `apps/vxpipe_call_engine`, always with `ERL_FLAGS='+S 2:2'` and
`MIX_BUILD_PATH` set to this isolated checkout's `_build` absolute path:

```sh
# Red 9/3, then green 9/0
mix test test/vxpipe/call_engine/plan_startup/output_stt_configuration_test.exs \
  test/vxpipe/call_engine/plan_startup/output_stt_format_test.exs --seed 0

# Compatibility: 54 tests, zero failures
mix test test/vxpipe/call_engine/plan_startup \
  test/vxpipe/call_engine/call_spec/sts_selection_test.exs \
  test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs --seed 0
```

Existing room tests were run unchanged. Only startup/new helper, focused tests,
scoped docs and this labnote changed. No conversion, new dependency, hosted call,
manifest enablement, root gate or overall milestone acceptance is claimed. Direct
low-level allocations bypassing PlanStartup are not modified by this checkpoint;
parent retains controller/finalization and broader acceptance ownership.
