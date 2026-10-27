# ElevenLabs progress timeouts

## Scope and decisions

- User approved replacing fixed speaking-duration limits with scoped stalled-work
  guards. Native turn detection remains solely provider-owned.
- Track caller finalization and response progress as separate usable checkpoints.
- Setup completed successfully. Initial worktree was clean.
- Repository documentation records only this adapter's contracts and evidence.

## Evidence

- Caller regression failed as expected: injecting the original speech-start
  deadline closed the active provider with `:session_failed` before more PCM
  could be accepted. The fix arms that deadline only on native stop and ignores
  caller timeout messages while the caller is still speaking.
- Caller focused suite: 20 tests pass. The first green attempt exposed a test
  ordering error: acknowledge the input transcript before expecting turn end.
  Corrected the harness ordering; no implementation change was needed.
- Independent GPT-6 Astra xhigh review cleared caller code/tests/documentation.
  Response design review requires preserving ambiguous-origin failure and
  exempting completed tool-only responses from speech-transcript deadlines.
- Format, compile and strict Credo pass. The first full umbrella run observed a
  Gateway CallIngress failure; targeted and complete final reruns passed below.
- Response regressions: initial eight cases produced five expected fixed-deadline
  failures; adding the native-origin and tool-only design cases produced seven
  failures across eleven tests. All eleven pass with scoped progress deadlines.
  After green, replaced the temporary legacy-expiry helper with actual scheduled
  opaque timer references; queued and completed obligations are asserted absent.
- All focused ElevenLabs tests pass: 145 tests, zero failures, four exclusions.
  Existing fixed-opening, room authorization, tool continuation and cancellation
  tests remain green. No live provider requests were made for this change.
- Timer policy lives in a dedicated module. Session callback completion reconciles
  obligation fingerprints once; changing or removing one cancels its old timer.
  Provider audio progress uses a counter separate from buffered/delivered bytes,
  so draining the local queue cannot masquerade as upstream progress.
- Independent GPT-6 Astra xhigh source review of checkpoint B is clean, including
  the resolved native-origin and tool-only design findings.
- The first umbrella run completed 4,492 tests with one Gateway CallIngress
  failure (`:telephony_leg_unavailable` during cancellation/binding). The same
  test passed its targeted rerun; no Gateway changes were made. Acceptance waited
  for the complete final umbrella pass rather than relying on the targeted pass.
- Local tagged WebSocket admission test passes (one test); no hosted connection.
- Final combined source passes all five root gates and Lean: format,
  warnings-as-errors compile, strict Credo, 4,503 tests with zero failures and
  159 exclusions, unused dependency check, nine Lean build jobs and one oracle
  replay. Gateway passed all 863 tests on the complete final run. No Gateway code
  or test changes were needed.
- Final independent GPT-6 Astra xhigh review verified both checkpoint diffs,
  documentation and gate logs and returned CLEAN: no remaining actionable code,
  test or contract findings. Persisted as separate caller-finalization and
  response-progress checkpoints with the synchronized milestone/index.
