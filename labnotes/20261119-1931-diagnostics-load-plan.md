# Diagnostics load plan and isolation

## Scope and decisions

Prepared the pre-measurement portion of milestone E in
[the measurement plan](../docs/design/latency-diagnostics-measurement-plan.md).
Recorded hardware, both reuse/fallback modes, room/source concurrency, repeated
warm/cold paired phases, numerical CPU/RSS/p95 budgets and positive coverage
requirements. No load harness or benchmark results exist for this checkpoint.
No production service or provider configuration was changed.

Source inspection confirmed Ortex model init/run use DirtyIo, with tensor binary
conversion on DirtyCpu. In-process tasks cannot contain native VM faults. Retired
ActivityRuntime jobs retain admission until DOWN, so timeout is not a native
termination guarantee. External-process isolation remains an alternative if the
budgets fail or native fault containment becomes required.

Corrected the runtime-limits document's stale pre-cutover status and coordinator
reference to the implemented room service. The separate effective-disable clock
assumption remains unresolved and unchanged.

## Verification

- Hardware inspected using lscpu, free, kernel/runtime versions and user-service
  cgroup limits; these are environment observations, not load measurements.
- Focused ActivityRuntime tests: 8 passed, zero failures, seed 158305. These
  exercise task/admission contracts, not native VM crash containment.
- Local documentation links and `git diff --check` pass.
- Independent Astra xhigh design review found no remaining blocking issue after
  the corrections below. The isolation-choice task can close independently;
  measurements, stress, acoustic accuracy and live gates remain open.
- Review found stale wording claiming every runtime subtree was outside call
  lifecycle. Reproduced against `RoomIncarnationSupervisor` composing the optional
  `Diagnostics.RoomSupervisor`; corrected the text to distinguish room-owned
  observers from shared inference/persistence.
- Review found that cold accounting from first accepted audio excludes operational
  model warmup. Reproduced in `Speech.ConversationalSTT.prepare_detector/1` and its
  warmup result/activation path: initialization precedes accepted input. Changed
  cold resource accounting to begin before room/STT preparation, with a separately
  defined 20-second audio window and explicit startup limits. Also clarified that
  a phase requiring no model must not fail a model-readiness requirement.
- Clarified that only diagnostic model loading is excluded from room readiness;
  operational Silero retains its existing STT readiness behavior. Reviewer also
  independently checked the pinned model file checksum against the plan.
- No full suite, live provider tests, Telnyx calls, benchmark load or deployment.
