# Configured diagnostic writer crash

## Scope and decisions

Added four configured-call acceptance cases: local operational Silero off/on,
each with diagnostic collection off/on. Enabled cases persist a canonical turn,
kill the actual diagnostic writer, continue input and response before waiting for
reattachment, then persist a turn in a different run. Writer capacity is one, so
recovery also checks release of the old slot. Disabled controls allocate no writer
and persist no diagnostic runs.

The test checks exact provider PCM and correlated transcription/response text for
three turns, operational versus fallback inference, no duplicates after teardown,
no extra provider commits, and released source/inference/write capacity. The
public authorized Calls read API must report the original unclosed run as
`unconfirmed` with `stale_heartbeat` after the real freshness interval. It must
retain only the pre-crash turn; the test never rewrites stored timestamps.

This is a crash of an idle writer after a real persisted turn. The separate writer
unit case covers abrupt death during a blocked database task. Neither case proves
native fault isolation, measured memory/CPU overhead or the complete stress gate.
No runtime behavior or Telnyx code changed; no live provider calls were made.

## Test development and evidence

- Initial four-case run: three passed, one failed because killing a writer while
  its task borrowed the shared SQL sandbox transaction disconnected that transaction.
  Production has separate database connections. The fixture now suspends the
  collector, waits for the writer's public handoff reservations to drain, kills
  the writer and resumes the collector in `after` cleanup.
- Next run: three passed, one failed because normal call completion could outrun
  pending benchmark inference before the deliberate crash. The helper now waits
  for the before/after inference evidence before crash/teardown. Inference during
  reattachment may legitimately be absent; duplicates are still rejected.
- Focused configured writer-crash cases: 4/4 pass, seed 460123, 22.7 seconds.
- Writer and coverage component cases: 21/21 pass, seed 862553. This includes
  abrupt writer death with a blocked task and independent stale-heartbeat rules.
- Root format, compilation with warnings as errors, strict Credo and unused-lock
  checks pass. Changed milestone relative links and `git diff --check` pass.
- Independent Astra xhigh review is clean. Its configured rerun passes 4/4,
  seed 460123, 22.5 seconds. Review confirmed the idle-crash ordering, recovery,
  authorized stale-heartbeat reads and final duplicate/resource barriers. No
  additional finding required a reproduction or runtime change.

No full suite was run: the user deferred it until milestone implementation is
complete. This checkpoint leaves broader failure-parity, stress/load and live
acceptance open.
