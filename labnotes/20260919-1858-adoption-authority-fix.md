# Adoption authority fix

## Authorization and reproduced failure

The user authorized fixing the paused adoption defect and required a load test
afterward to check for collateral failures. Existing room consumers remain on
the legacy path; this work repairs the new isolated R implementation.

Reproduced the original red test before changing implementation: the old lease
closed the adopted tree, monitored termination arrived, and the new consumer's
input returned `{:error, :closed}`. Expanded tests then ran red: 12 tests with
four failures (old lease close, failure recipient, consumer lifetime and altered
handle fields granting close authority).

## Correction

- ScopeControl stores current phase, lease and consumer alongside the immutable
  allocation identity. Close checks that stored identity and current authority.
- Channel synchronously commits activation/adoption through ScopeControl before
  enabling delivery. Controller validates the actual channel, exact allocation,
  expected authority, owner/lease/consumer liveness and the original deadline.
- Activation settles the cancellation token and startup timer, drops the lease
  monitor and installs the consumer monitor. Lifetime ownership stays intact.
- Failure notifications use current authority. Speech data still travels through
  allocation-local workers; no per-audio controller call was introduced.
- Rejected fixes: updating only Channel leaves split authority; removing lease
  close entirely breaks pending cancellation; async settlement permits adoption
  to return before close authority has transferred.

## Verification in progress

- 12 lifecycle tests passed after the fix. The combined lifecycle/native STT
  group passed 29 tests. The full focused speech group then passed 45 tests.
- Adapted old prototype tests and standalone latency harness to explicit scopes
  and asynchronous readiness. Preserved PCM/event assertions and the legacy
  benchmark path. Startup latency is measured through readiness, not just the
  return of `:starting`. Eight healthy jobs reached ready in 0–1 ms while the
  unrelated initializer was held; same-scope sibling recognition also passed.
- Replaced Agent-based event recipients with a forwarding test actor: Agent can
  discard events before a callback receives them. This prevents a fixture race
  from weakening recipient/ownership assertions.
- GPT-6 Astra xhigh independently reviewed the bounded correction by inspection
  and found no blocker. This does not accept all of checkpoint R.
- Added an opt-in adoption load harness with 1/8/32 scopes, direct/adopted paired
  repeats, independent E PCM, active sibling input during candidate churn,
  old-lease close/death, exact event/generation checks, descendant monitors and
  empty child-supervisor checks. Burst and 20ms PCM-chunk lanes are separate;
  active input deliberately pauses while its candidate runs. Results below.

## Load results and acceptance limits

- Adoption load passed 16,236 measured turns in 137.2 seconds. All 36 trials
  returned to 245 processes; post-trial memory was 85.3–90.7 MB. Provider/tree
  monitors and empty allocation/lease supervisor checks passed.
- At 32 scopes with adopted candidates, healthy sibling turn-end processing was
  p95 1.917 ms / p99 3.122 ms burst and p95 0.739 ms / p99 0.999 ms paced. Old-lease
  close rejection p95 was 0.428 ms burst and 0.251 ms paced. No correctness or
  deadline failures occurred in the tested workload.
- Two complete runs of the retained legacy/native benchmark each passed 68,400
  measured turns. The first included one held-peer outlier repeat (text p95
  9.684 ms, end p95 4.864 ms); the follow-up did not reproduce it. Retain both raw
  reports and do not infer causality from the outlier alone.
- Follow-up at 32 owners: legacy/native first-text p95 2.013/2.677 ms; turn-end
  p95 1.511/1.615 ms. Scoped overhead remains measurable; no overall speedup or
  production capacity claim is made.
- Durable decision, methodology, results and report links live in
  `labnotes/20260919-1220-speech-adoption-fix.md`. The machine was Apple M2, 8 cores, 16 GiB RAM,
  with 8 online BEAM schedulers.
- Root format, warnings-as-errors compilation, strict Credo (992 source files)
  and unused-lock checks passed. Full umbrella tests passed: 1,845 tests,
  zero failures, 40 excluded, seed 877669. Call Engine passed all 747 tests
  (12 excluded), including the two extra expiry/lifetime tests.
- This is the user-authorized repair and load-verification slice. R remains
  unaccepted: full private-init/race, ancestry and allocation/capability failure
  matrix/timing evidence is still required before its Exit checkbox is checked.

- Final GPT-6 Astra xhigh review found no blocker to the bounded repair checkpoint
  and verified report counts/metrics. Corrected pacing metadata to say 20 ms waits
  after completed pushes (plus processing), and described retained results as
  percentile summaries because individual samples are not stored. Timing values
  were unchanged; no load rerun was needed for these wording corrections.
- The reviewer identified concrete remaining R deadline implementation work:
  `Session.close/1` currently catches a control-call timeout as success, and
  input-failure cleanup receives a fresh timeout budget. These are outside the
  verified adoption correction, remain open, and prevent accepting R for room
  migration. No stalled-control reproduction or contrary safety claim is made.

## Checkpoint outcome

The user-authorized adoption repair is verified and can be recorded as a coherent
experimental checkpoint together with the previously uncommitted local-scope
foundation it requires. It does not accept milestone R or authorize room
migration. No source behavior changed after the successful load runs; subsequent
changes were formatting, additional test cases and corrected report metadata.
All five root gates passed on the repaired implementation. Local Markdown links
and `git diff --check` passed. No hosted/network acceptance or capacity ceiling
is claimed.
