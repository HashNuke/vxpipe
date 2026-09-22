# Google origin cutover

## Decision and scope

The opted-in Google STS adapter used to pin its first opaque interaction
context for the socket lifetime. A fake-wire controller test reproduced
permanent `:busy` after A had ended, its response had played, and the engine
had released a hold. Permit B to bind on the same socket only at explicit
model `IDLE` plus a complete turn and no caller, tool, response or playback
obligation. Preserve A during `IN_PROGRESS`, retained playback, pending tools,
or ambiguous interruption. Rejected operations neither send nor change origin.

The first implementation admitted C after B PCM was accepted if a second,
uncorrelated `IDLE` arrived before B produced model content. The focused red
returned `:ok` where `{:error, :busy}` was required. Keep a boolean unresolved
accepted-input obligation for opted-in sessions. Actual input sends and tool
results set it; model content, output transcript, or tool call clears it. A
bare `generationComplete` or `IDLE` cannot clear it. This intentionally blocks
silent response cutovers/renewal; the unlabelled wire cannot prove they were
fully processed.

A read-only reviewer reproduced a separate same-context renewal defect: with
an open typed input turn, `goAway` set `renew_requested?` but subsequent PCM
was accepted and sent on the retiring wire. Focused controller red: 1 test,
1 failure (`:ok` instead of `{:error, :busy}`). The opted-in input guard now
rejects new PCM, text, and activity starts during renewal and all activity
during socket replacement. Ending an already active caller remains allowed so
it can settle. Fresh activity-end is blocked.

## Verification and limits

- Initial A-to-B focused red reproduced `{:error, :busy}` for settled A;
  first cutover implementation made controller tests green (69/0).
- B-to-C late-`IDLE` focused red reproduced unexpected `:ok`; model-content
  obligation implementation made the targeted 27-test selection green.
- Same-context renewal focused red reproduced unexpected `:ok`; guard made
  the targeted test green. Controller suite: 72 tests, 0 failures.
- Before the renewal guard, the wider ten-file Google/provider/shared group
  passed 272 tests, 0 failures after adapting tool-only silent-response
  expectations to require actual later model content. After the final guard,
  the full call-engine child suite passed 1,405 tests, 0 failures, with 30
  integration tests excluded.
- These are local ordered fake-wire proofs. The reviewer could inject late A
  text/PCM after B cutover and observe B attribution, but no evidence yet
  establishes that such post-`IDLE` A content is valid Google Live behavior.
  Do not claim hosted causal attribution or resumption-handle coverage.
