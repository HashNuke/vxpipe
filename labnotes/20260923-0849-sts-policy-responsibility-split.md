# STS policy responsibility split

The post-`4f375877` root run passed format, warnings-as-errors compile and unused-lock checks, but strict Credo reported the room STS module at 810 lines and the capability STS module at 806 lines against its 800-line limit. Root `mix test` stopped before running suites because the local PostgreSQL SCRAM test connection has no password configured; this is not a test pass.

This checkpoint extracts room activity-origin retirement/recovery into `RoomAuthority.SpeechToSpeech.OriginRecovery` and capability policy transition/fencing into `Capability.SpeechToSpeech.Policy`. The existing public delegation and GenServer reply shapes are preserved. No intended runtime behavior changes; the parent modules are now 738 and 776 lines. The adjacent five-file room/capability/turn-control group passes 104 tests, zero failures, on seeds 0 and 1. `git diff --check` passes.

After this commit, rerun the root static gates and report the PostgreSQL-backed root test gate separately. The independently reproduced agent presence-loss/regrant issue is a separate behavior checkpoint; do not conceal it inside this mechanical gate repair.

Post-commit `6752771e`: root format, warnings-as-errors compile, strict Credo (1,102 source files, no issues), and unused-lock gates exit 0. Root `mix test` again exits before suites at PostgreSQL SCRAM authentication because no local test password is configured. This is the unchanged environment blocker, not a successful umbrella test run.
