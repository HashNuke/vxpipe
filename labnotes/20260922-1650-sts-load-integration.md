# STS load integration

## Scope and review

Reviewed Astra's isolated harness commits `962c98d4` and `9f0ff524` and
cherry-picked them as `138c0896` and `9908a1a1` after the local tool, recognizer
and admitted-output-policy checkpoints. Both milestone merges were automatic;
the main worktree was clean before integration. No production runtime changed
in the harness commits.

Read the methodology and all support modules. Requested two follow-ups before
integration: capture input time before feeder creation and prevent delayed
caller/public onset from being attributed to a new input after sink audio;
replace scheduler-dependent 200 ms sink assertions with a controlled clock,
exact finish tokens and acknowledgement barriers. The returned regressions
cover both event orders, independent namespaces, unknown/duplicate correlation,
old finish during replacement output, and explicit test-supervisor names.

## Integrated verification

At `9908a1a1`, root format, warnings-as-errors compile, strict Credo and unused
lock checks pass. `bash -n bin/sts-call-load` passes. The four focused harness
test files pass **seven tests, zero failures**, seed 0, two schedulers.

`bin/sts-call-load smoke` passes **three tests, zero failures** in 25.1 seconds
against the integrated STS fixes. Every mode (`llm_tts`, `sts_provider`,
`sts_output_stt`) reports two ready calls, five completed turns, two
interruptions, one healthy survivor, two cleaned calls and no errors. Mode
elapsed times are roughly 8.7, 8.1 and 8.1 seconds respectively; these are smoke
observations under concurrent development, not comparative performance claims.
Temporary logs: `vxpipe-sts-load-integrated-contracts.log` and
`vxpipe-sts-load-integrated-smoke.log`.

The actual ten-call measurement is still pending a coordinated quiet window.
Asked the Gateway agent for a window after its currently live native run ends;
do not interrupt or restart a test to manufacture one. The complete umbrella
gate remains pending review/integration of that agent's handoff repairs.

## Continuing parallel ownership

The completed load and read-only audit agents are closed. The audit returned
exact fake-Google-controller and recognizer-usage probe snippets; their
reproduction methods are already milestone tasks, not claimed fixed by these
commits. Parent owns output lifecycle/retirement and shared tool execution.

Started native Codex Astra medium agent Boyle on
`sts-parallel-google-config-20260922` at `9908a1a1` for the existing private
agent prompt/tool-schema configuration task. Its scope is startup/runtime
configuration and Google setup/session plus focused tests/docs; no capability
output files, room STS, shared invocation machinery, Gateway, load harness or
normative provider contract edits. The parent synchronizes the latter after
review. No hosted call, credential inspection, manifest enablement or history
replay is authorized. Each new implementation remains tasks-before-code,
red-green and coherently committed before broader gates.
