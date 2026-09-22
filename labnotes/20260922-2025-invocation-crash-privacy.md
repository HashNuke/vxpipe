# Invocation crash privacy

Parent approved a separate narrow repair after `96fb0395`: only Invocation's
format_status/1 runtime callback plus owning crash/redaction regression tests.
No execution, timer, outcome, startup/private-handle or provider changes.
This isolated worktree retains its independent build and dependency copies.

## Design review before tests/code

The previous real STS supervisor-kill check logged Invocation state containing
arguments. Test the actual GenServer/Logger path using synthetic argument and
diagnostic-message canaries, captured logs, and process monitors. Require a real
crash report so an empty capture cannot falsely prove privacy. Also exercise
worker termination under a surviving supervisor to inspect its child report.
Use status with sys diagnostic logging enabled and explicitly test sanitization
of all four formatter fields. Do not suppress logging, modify execution, or
change failure classification. A remaining startup/child-spec leak requires a
new exact scope request before editing those generic boundaries.

The milestone repair task and this separate design review precede tests/code.
Run red first, add the formatter, then run owning Invocation checks plus the
previous 83-test selection only, with ERL_FLAGS='+S 2:2'. Root acceptance and
independent review remain parent-owned. Commit the repair separately.

## Red/green evidence

All Mix commands ran from the isolated owning `apps/vxpipe_call_engine`
directory with its copied build/dependency directories and two schedulers.

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/tool/invocation_redaction_test.exs --seed 0
```

- Initial fixture run 49613 exited 1: required Context fields were omitted.
  Corrected the fixture before claiming any behavioral red.
- Red 64469 exited 2: four tests, four failures. Captured actual GenServer
  reports on parent loss and worker termination contained the synthetic
  argument. Diagnostic status also exposed it; the formatter was absent.
- Added only Invocation.format_status/1, sanitizing state/message/reason/log.
- Intermediate 97449 exited 2: actual crash captures and formatter passed;
  raw OTP debug ring remained visible in explicit sys.get_status introspection
  after sys.log was enabled. The formatted state and logged-events section were
  redacted, but the raw debug field is outside this callback's control.
- Refined the diagnostic assertion to ordinary formatted status; strengthened
  BOTH actual crash tests by enabling sys.log and placing a synthetic private
  message in its ring before termination. Captures require a real GenServer
  termination report, absence of argument/message canaries and monitored DOWN
  for both Invocation and action Task. The worker-termination path also waits
  for the surviving supervisor to handle the termination before ending capture.
- Green 91647 exited 0: all four tests pass. The raw VM debug-ring limitation
  is explicitly documented; no startup/private-handle expansion was attempted.

Final requested selection, 41938, terminal exit 0: 99 tests, zero failures.
This includes the previous 83 cases and 16 owning Invocation cases:

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/room_authority/sts_tool_lifecycle_test.exs test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs test/vxpipe/call_engine/capability/speech_to_speech_test.exs test/vxpipe/call_engine/tool/invocation_redaction_test.exs test/vxpipe/call_engine/tool/invocation_supervisor_test.exs test/vxpipe/call_engine/tool/invocation_registry_test.exs --seed 0
```

The previously argument-bearing STS supervisor-loss report now contains only
redacted reason/message and `:tool_invocation` state. No child-start argument
leak appeared in either captured crash path. This is evidence for the reported
crash-log boundary, not all malformed startup paths or privileged VM diagnostics.
No real credentials or private user data were used.

## Review and checkpoint

Local diff review: runtime change is exactly the nine-line formatter addition;
all execution/timeout/reporting/termination functions are unchanged. Tests reuse
the existing controlled host tool and restore its observer configuration.
Exact-file formatting and whitespace checks pass. Parent owns independent review
and root acceptance. Keep `96fb0395` unchanged; this repair is a separate commit.
Full STS running acknowledgement/private continuation/admission remains OPEN.
