# Handoff release policy

## Reproduction

The previous goal turn committed initial caller waiting and incoming leg lifetime fixes
(53cceb8 and 7c81360), with all five gates passing. Revalidated those commits and preserved
another agent's documentation-site/visual-note changes.

The release worker adopts prepared connections, collects the old graph and compares the current
policy to the committed candidate. A policy revision at this boundary returns an error and closes
the room, even before any media gate was released. The approved contract requires reconciliation
under the same attempt deadline and a fresh cue. Add two exact-boundary cases to the existing
human-handoff cue tests: removed STT demand and an unrelated observer admission. Defer the test
connection's adoption acknowledgement, revise policy after commit, then require a second cue and
successful activation while retaining healthy instances. This introduces only an opt-in fixture
acknowledgement; no production test hook or UI change.

- Red: both post-adoption policy cases miss the required second cue (2 tests, 2 failures;
  vxpipe-release-policy-red.log). The first fix passes both: use current authoritative resources
  while keeping receipt identity, phase, deadline and source resources intact.
- Added a still-required STT permission change, requiring exactly one affected replacement and
  its explicit readiness acknowledgement; unaffected room/connection instances remain unchanged.
- The expanded run exposed a lost readiness notification after retry: cue validation consumed
  the collector's ready event, then release awaited another without requesting a probe. The
  collector correctly suppresses duplicate unchanged reports. Refresh explicitly before the
  final closed-gate release probe; do not wait for an event that may never arrive or extend timeouts.


## Design review

After policy adoption, reconcile against the current authoritative policy using the existing
live-resource preparation path. Candidate installation and participant promotion have already
happened; repeating either would add unnecessary lifecycle work and could restore obsolete
permissions. Keep the original destination receipts for completion, and retain the same phase,
attempt, deadline and held output generation. Newly included listeners are held before their
waiting/cue audio starts. Removed source or destination identity is not silently reconstructed.

Only stale policy or room binding before the first release can take this retry. The actual
connection-release loop stays outside the retry, so any failure after it starts closes the room
under the existing uncertain-admission contract. This checkpoint does not claim all partial-release
failure injection, capability kinds or changing-listener scenarios are accepted.

## Native and focused evidence

- Three embedded post-adoption cases pass: no-longer-demanded speech, unrelated policy, and a
  still-required recognizer with changed transcript permissions. They require a fresh cue, the
  original deadline, unchanged room services/connection owners and no extra STT transport.
  The permission-change case requires exactly one affected replacement and its acknowledgement.
- Focused human-handoff, agent-handoff and readiness-inventory run: 61 tests, zero failures
  (`vxpipe-release-policy-focused.log`).
- Native peers pass the same three policy cases and exchange 500/1500 Hz audio after activation
  (`vxpipe-release-policy-native-required.log`, three tests, zero failures). The native fixture
  uses a bounded, one-use OTP system debug callback at the Gateway adoption request; production
  exposes no test hook. Removing demand before admission discards private speech actors; removing
  it after adoption uses the existing main-room speech lifecycle and retains its reusable actors.
  Unrelated media input/output/codec actors are retained in both cases. The still-required changed
  recognizer reports a preparing blocker until its replacement transport acknowledges readiness.
- All five umbrella gates are running. No development-server restart or UI changes were needed.

- The first root run (seed 235296) passes format/compile/Credo and all 628 engine tests, but one
  of 369 Gateway tests sees an intermediate `preparing` update with an empty blocker list before
  the new STT probe reports. This is valid progress, not readiness or a transfer completion. The
  native assertion now waits within its original bounded deadline for the specific speech blocker
  before acknowledging the replacement. The rest of the 1,368-test run passes; no completion
  gate is claimed green until the final rerun.

- The corrected three native cases pass with the previously failing seed 235296
  (`vxpipe-release-policy-native-final.log`). The final umbrella rerun pins that seed too.
- Next failure-stage audit should cover policy/membership changes while connection-release
  acknowledgements are in flight. The current retry ends before that loop; its successful return
  currently checks the attempt identity. Do not infer complete partial-release fencing from
  this checkpoint's before-release policy cases.


## Existing recovery failure during completion checks

The next full umbrella run passes the new policy cases but fails the existing native
`destination` loss recovery case: `await_recovered` observes `handoff_recovery_failed` when
reading the room (seed 235296; `vxpipe-release-policy-final-test.log`). This resembles the
already-open intermittent recovery concern, but no cause is established by that resemblance.
A temporary atom-only diagnostic on recovery worker errors and 16 bounded single-case runs
(`--repeat-until-failure 15`, `vxpipe-recovery-audit.log`) all pass. This does not prove the
failure fixed. Run the full native file with the same diagnostic next; remove temporary
instrumentation before any implementation commit. Keep recovery acceptance open.

- The full native file also passes all 37 cases at seed 235296 with the temporary atom-only
  diagnostic (`vxpipe-recovery-file-audit.log`); no recovery worker error is reproduced. Removed
  that instrumentation. No recovery implementation or restoration budget was changed. The
  intermittent full-suite failure remains unresolved in the human recovery acceptance task.


## Final checkpoint verification

After removing temporary instrumentation, all five root checks pass: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The final run has 1,368 tests, zero failures and 15 exclusions
(`vxpipe-release-policy-verified-*`). Counts: MCP 37, agent runtime 91, engine 628, Calls 81,
Gateway 369, artifacts 19, persistence 49 and Console 94. No code or test changed after this run.

The milestone retains 24 open checkpoint tasks. Update its latest evidence and index without
claiming complete human-handoff or recovery acceptance. Commit the policy-reconciliation behavior,
three engine/native cases, documentation and this note together. Preserve the other agent's five
site/visual-note paths. The intermittent recovery failure remains a specific follow-up despite the
passing final run; no fix is inferred from repetition.
