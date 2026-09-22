# STS Google integration

- Main baseline was clean at `bb87d6fb`. Integrated native Astra implementation
  `dd501d39` as `e5cb0993`, then name-validation review repair `2bd28042` as
  `13969fdc`. Inspected exact staged changes and checked whitespace before each
  commit; milestone changes merged without losing concurrent runtime tasks.
- Independent Astra xhigh review of the fixed name validation found no further
  scoped issue. The adapter uses full-string anchors and tests construction,
  tampered structs and failure before socket connection. The original reproduction
  and red/green results remain in the implementation labnotes.
- Added an explicit integration/contract-sync subtask before updating the
  normative provider contract. No additional runtime behavior was changed here.
- Integrated focused startup, selection, Google codec/session/output and shared
  STS conformance/output group: **90 tests, zero failures**, seed 0, two schedulers.
  Command ran from the Call Engine child:

```sh
ERL_FLAGS='+S 2:2' mix test \
  test/vxpipe/call_engine/plan_startup \
  test/vxpipe/call_engine/call_spec/sts_selection_test.exs \
  test/vxpipe/providers/google/sts_test.exs \
  test/vxpipe/providers/google/sts_session_test.exs \
  test/vxpipe/providers/google/sts_output_test.exs \
  test/vxpipe/call_engine/speech/sts_conformance_test.exs \
  test/vxpipe/call_engine/speech/sts_output_test.exs --seed 0
```

- Main's earlier all-five-gate pass (2,282 tests, zero failures) belongs to
  `4f5d2fb1`, not this integrated source or the later completed-recognition repair.
  A new post-commit umbrella pass is required and will be recorded separately.
- No hosted requests, production Google manifest/badge enablement, history/audio
  replay, or new tool execution authority. Private-policy continuity and output-STT
  private startup configuration continue in separate agent worktrees.

## Post-commit umbrella result

All five root gates passed on clean committed `9ffe2ab4`: format, warnings-as-errors
compile, strict Credo, unused-lock check and the full test suite. Tests: **2,299,
zero failures, 45 excluded**, seed 0. Call Engine contributed 1,139 tests and
Gateway 492, both with zero failures. The run completed with exit 0; output is in
`vxpipe-sts-google-integration-umbrella.log`. No main source/build changes occurred
while the run was active. Commands used `ERL_FLAGS='+S 2:2'`, with
`PGHOST=/var/run/postgresql` for tests.

This result covers the preceding completed-recognition repair plus integrated
Google configuration. It does not cover later sidecar/private-policy worktree
commits or close the separately reproduced native handoff and Google controller
gaps. Independent Astra xhigh review of sidecar commit `afd721c1` found no scoped
defect; its integration follows this recorded baseline.
