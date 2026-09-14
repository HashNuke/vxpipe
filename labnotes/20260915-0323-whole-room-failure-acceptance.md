# Whole-room failure acceptance

## Scope

Extend the existing three-peer native handoff acceptance with failure of the destination STT,
remaining participant STT, or enabled local recording writer during preparation, adoption and
release. Preserve the ordinary default/custom/nil success cases. The input and private-audio checks
run before each failure. During release the actual output arbiter is already open while the
connection acknowledgement is paused, so the case proves partial-release teardown.

## Evidence so far

- Six remaining-participant/recording loss cases pass. Provider loss waits for actual transport
  termination before unpausing adoption/release; writer failure changes its readiness contract to
  failed. Every peer closes without activation, caller completion, replacement speech or redial.
- Two destination STT loss cases after adoption and during release also pass.
- Red: destination STT loss during preparation fails source recovery in the three-peer recorded room.
  Both remaining resources were made ready, so the original source conversation should recover.
  The authority instead stops with `handoff_recovery_failed`. Diagnose this without increasing the
  existing 750 ms recovery budget or removing the remaining listener/recording requirement.

## Recovery defect and bounded fix

A temporary atom-only diagnostic localized the native failure to recording preparation; it has
been removed. The recording actor retained a failed preparation reservation after the transfer
phase ended. Its live-track preparer rejected every non-nil reservation, including failed ones,
so the original recorded conversation could not pass recovery readiness. Two focused engine cases
also reproduced conflict when restoring current tracks or preparing a fresh candidate.

Allow current-policy track preparation alongside a failed reservation, preserving its rejection
of stale candidate adoption. Mixer and recorder preparation may replace a failed reservation only
for a different owner, after validating the current candidate. A failed owner cannot revive its
old lease. New preparation gets a new token and retained live writers keep their readiness/sequence.
Active reservations still conflict. No runtime process restart, deadline extension or UI change
is introduced. The two focused engine cases passed; native recovery then exposed the additional
listener issue below.

## Three-peer recovery follow-up

With recording preparation repaired, recovery reached ready but the remaining listener crashed
on an authorized assistant `TextOutput` event from the caller's turn. Gateway only handled its own
connection's assistant text. The added handler forwards same-room main-admission transcripts without
projecting another connection's speech lifecycle into this listener's local turn queue. The native
case receives the text and verifies that queue remains empty.

A subsequent audio assertion incorrectly expected the caller's synthesized reply at the observer.
`AgentOutput` targets synthesis to the requesting connection's output sink. The test now verifies
the caller's cue followed by restored assistant speech, and the observer's cue followed by mixed
caller audio. Human audio also returns to the caller, the retained observer recognizer receives it,
and both original human recording tracks produce chunks. This changes the test expectation to
match the existing routing contract; it does not add assistant-audio broadcast. The focused native
case passes in 46.8 seconds.

The existing mixer phase-owner-loss case now attempts a fresh valid preparation before explicitly
discarding the failed lease. Without failed-lease retirement it reproduces `preparation_conflict`.
The failed original owner remains rejected; the new owner must receive a new token and stale
expiry/discard must not affect it. Full owning suites and root verification follow.

## Verification checkpoint

- Mixer fresh-owner retry reproduced `preparation_conflict` without failed-lease retirement.
- Owning mixer policy preparation, recording policy preparation and recording suites: 25 tests,
  zero failures, seed 235296.
- Focused native recorded recovery: one test, zero failures, 54 excluded; 46.8 seconds.
- Root format, warnings-as-errors compile and strict Credo pass. Full umbrella tests are running;
  the call-engine portion passes 639 tests with one integration exclusion.

The old intermittent recovery issue is not established as the same defect. This checkpoint proves
a deterministic failed-recording-reservation case and the additional-listener transcript boundary.

## Completed checkpoint

All five umbrella checks pass: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The full suite reports 1,396 tests, zero failures and 16 integration exclusions. Gateway reports
386 tests, including 54 default native startup/transfer cases. The nine resource-loss cases all
run in this default lane; the public-URL and live-provider exclusions remain separate evidence.
The runner results file `vxpipe-whole-room-failure-gates-results.json` records zero for every gate.

Mark the independent destination/remaining-participant/room delay-and-loss task complete.
The milestone and index now agree on 21 remaining checkpoint tasks: human 4, AI 3, phone 6,
changing/multiple listeners 6 and final audit 2. Keep the broader human failure/diagnostics and
private-resource tasks open. No UI change or dependency upgrade was needed. The other agent's
`vxpipe-docs` and visual labnote changes remain outside this checkpoint.
