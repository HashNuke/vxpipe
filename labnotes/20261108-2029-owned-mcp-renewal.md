# Owned MCP renewal

## Reproduced boundaries

- Queued preflight admission after caller death: the shared runner was suspended,
  the outgoing GenServer request was observed, and the caller was killed before
  resuming the runner. The callback still executed. Regression red: seed 552638,
  one expected failure (`vxpipe-owned-renewal-admission-red.log`).
- Exact session close while the shared renewal runner is suspended: the renewal
  callback survives the acknowledged close. The new regression uses a real
  scoped library session and Console renewal adapter with an explicit session
  option; the baseline adapter ignored that option. Regression red: seed 752803,
  one expected failure (`vxpipe-owned-renewal-close-red.log`).
- These agree with independent Astra probes; the isolated rerun seeds are 839190
  and 648291. No fix was written before reproducing them.

The two regression tests now live in their owner apps, after the preceding
explicit-host checkpoint completed its fixed-source root suite and was pushed as
`9b0b6215`. Their initial red results preceded implementation; both now pass.

## Reviewed direction

Reuse SessionOperation with a completion path that validates caller, deadline and
session without publishing readiness. Prepare from the original resolver before
any runner queue. The already-owned worker requests capacity from PreflightRunner,
then performs renewal itself; the shared runner retains bounded admission
metadata and monitors only. Independent management work retains its existing root
execution path. Add the exact runner PID to the existing lifecycle registration's
monitors so runner replacement cancels blocked workers without another watchdog.

Carry the explicit integration identity through both initial transport auth and
reuse, then through Calls credentials/refresh to Console run and token exchange.
Default DNS uses the existing resolve_direct hook inside another bounded owned
operation, preserving the DNS deadline. Mint token I/O already runs in its caller.
Preserve durable claims, completion/failure fencing and independent calls.

Implementation and final root verification are complete. Independent source and
test review finds no outstanding issues; final staged evidence review precedes commit.

## Implementation and intermediate evidence

- Initial four regression cases failed as expected, seed 95022: queued dead
  caller, close with stalled runner, timeout with stalled runner, and normal
  runner stop. Existing lifecycle/runner changes made all eight selected cases
  green, seed 86072.
- Three context-propagation cases failed before binding/port changes, seed 406752.
  Initial transport, reuse and Calls run/exchange propagation then pass alongside
  Console lifetime cases: ten tests, seed 38278.
- Both token DNS budget/teardown tests failed before the owned DNS adapter,
  seed 54581. The combined library lane passes 34 cases, seed 290045.
- The broader MCP protocol/lifecycle/conformance lane passes 287 tests,
  seed 43781, before the queued-budget correction below.
- Astra reproduced a pre-permit budget gap (seed 913828), independently rerun
  with seed 919076: a suspended runner delayed the configured timeout until its
  reply. The canonical queued-deadline/caller tests reproduced one expected
  failure (seed 916086). Each runner now publishes its immutable timeout in the
  existing Registry under its exact PID. The caller registers that budget before
  either queue; stale/missing records fail closed. The nine-test queued/deadline/
  DNS slice passes, seed 250080. No new coordinator or persistent-term cleanup.
- Expanded saved-grant boundary tests prove claimant retirement fences late
  completion and closing a nonclaimant session preserves the other renewal.
  The cross-node lane also exposed an existing startup-event ordering gap in
  its open/flush fixture; the deterministic reproduction and correction are
  recorded below.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks passed at this intermediate point. Root tests and final review had not
  yet completed, so these intermediate results did not change milestone status.

## Design review amendment

Independent GPT-6 Astra xhigh review favored session-owned execution with shared
admission records over the original root-worker cancellation protocol. Existing
SessionOperation admission, lifecycle monitoring, deadlines and descendant teardown
cover the work directly. The exact-PID timeout record was separately reviewed as
the minimal correction for pre-admission queueing. Remaining source review was
clean at that point. Final source and acceptance review found no additional
runtime issues and supports completing the durable refresh ownership item once
the final gates pass.

- The initialization-notification fixture race was reproduced by an isolated
  real-ExMCP probe, seed 116245 (Astra original seed 359832). The delayed old-token
  POST was `notifications/initialized`, already submitted before revocation;
  `tools/call` was rejected. The node open helper now awaits that notification
  before its mailbox flush. No transport authorization assertion was removed.
- Expanded Console boundary/node/owned work lane passes 23 tests, seed 708070
  (`vxpipe-owned-renewal-console-green.log`). This includes both delegated and
  machine session-owned renewal on two BEAM nodes, held response release after
  session close, unchanged durable claim fencing and preservation of the second
  session. The direct owned-preflight/readiness file passes 3 tests, seed 250914.
- Source design review is complete. The milestone's
  full credential/late-tool matrix, queued catalogs and final manual/performance
  gates remain open; these results do not claim full milestone completion.

- Final MCP owner-app run (all `test/vxpipe/mcp` and `test/integration`, with
  `--include integration`) passes 290 tests, zero failures, seed 461380
  (`vxpipe-owned-renewal-mcp-final.log`). This includes official conformance,
  connection-check and previous startup/retirement/transport lanes with the
  exact-PID configured-budget fix applied.

- Saved runtime/transfer/in-flight/boundary/phone and renewal boundary regression
  checks pass 29 tests, seed 87759. Calls credential/catalog/renewal checks pass
  20 tests, seed 965730. Independent queued-close review passes one case,
  seed 364743: close observes the queued worker's DOWN before returning, and
  resuming admission does not invoke its callback. That case is retained in the
  owned preflight regression matrix.
- The final queued matrix passes four tests, including close before admission;
  the mechanically updated Console renewal boundary file passes all seven tests.
  Final independent review approves those test changes and the reconciled design
  wording without runtime findings. Final umbrella evidence follows below.

## Final gate investigation

- The first full umbrella run completed 5,068 tests with one failure and 344
  excluded, seed 93634. The only failure was the existing Gateway outgoing-leg
  retry test: its observer monitor delivered `:noproc` instead of `:normal`.
  All other applications passed. The root command's output was captured through
  tool-session chunks; some large chunks were truncated. The exact failure is
  retained in `vxpipe-owned-renewal-root-failure.log`.
- The isolated failing test passes on the same seed. All 56 cases in its
  containing file also pass on that seed (`vxpipe-owned-renewal-outgoing-final.log`).
  Independent Astra investigation did not reproduce the interleaving and found
  no justified production or test correction. No assertion was weakened.
- The full repeat of unchanged source passes 5,068 tests, zero failures and 344
  excluded, seed 478700 (`vxpipe-owned-renewal-root-rerun.log`). The first-run
  interleaving remains unexplained; this evidence does not claim it was fixed.
- All four non-test root gates pass in the final run
  (`vxpipe-owned-renewal-fast-gates.log`). The durable OAuth ownership item is
  checked and the index records 10 of 29 implementation items complete.
  Final staged evidence review precedes commit. The next embedded restart-source
  research labnote is separate and excluded from this checkpoint.
