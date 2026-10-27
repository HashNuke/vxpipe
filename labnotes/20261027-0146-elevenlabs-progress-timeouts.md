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
- The first full run observed one Gateway CallIngress failure. Its targeted
  rerun passed, followed by a clean full run on the final combined source before
  either checkpoint was committed: 4,503 tests, zero failures, 159 exclusions.
  Format, compile, strict Credo, unused dependency check and Lean also pass
  (nine build jobs and one oracle replay). The response checkpoint records the
  remaining implementation and final independent evidence review.
