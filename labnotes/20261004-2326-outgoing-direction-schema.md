# Outgoing direction schema

Inspected the milestone/index, harness decision, existing CallSpec parser, compiler, participant
and connection intent, Calls route derivation and prerequisite milestone contracts. D is divided
into schema compatibility, plan/persistence, room lifecycle, Gateway media/outcomes, API and
idempotency, then observability; live acceptance follows these local checkpoints.

Drafted seven focused schema tests and ran them from CallEngine before implementation. All
seven failed as expected: new direction blocks are unsupported, the new version is rejected,
and the existing CallSpec has no explicit direction. The cases cover atom/JSON input, exclusive
direction blocks, references/connection intent, outgoing admission/opening defaults, timeout
bounds, transfer preservation and legacy parsing.

Before implementation, the user requested prioritizing real carrier provisioning and checking
the six named environment settings. Removed the newly drafted failing test from the worktree
while implementation is deferred, leaving the umbrella usable. No runtime change made.
Resume D1 by writing/running these focused tests again. Current provisioning evidence is in
the telephony-provisioning-check labnote and milestone; Twilio Trust Hub approval remains needed.

## Resumed implementation

Restored and reran the seven schema cases: seven expected failures before implementation.
Added a cohesive Direction parser/validator rather than expanding the main CallSpec with
direction-specific branches. It translates legacy entries into an incoming description, rejects
cross-version fields, and passes trusted participant context for outgoing admission and opening
defaults. Existing internal entry field names stay intact. Incoming version-specific connection
validation is strict for new source and preserves the older entry contract for legacy source.

- Schema/CallSpec compiler group: 71 tests, zero failures before the additional plan assertion.
- Added plan compilation assertion red on missing `direction`; explicit fields now propagate
  through compilation. Codec assertion went red on missing historical defaults, then passed
  after fixed-atom loading and incoming/no-timeout normalization.
- Calls new outgoing save/publication first failed on missing direction metadata. Now no inbound
  callee route is generated, and new/legacy sources save and publish beside each other.
- Calls focused group: 10 tests, zero failures; includes deterministic preparation digest changes
  with the ring deadline and checks the actual serialized-plan hash.
- Existing fixtures using old entry fields explicitly pin `20260915.01` instead of the changing
  latest-version accessor. This preserves their compatibility coverage. Two schema-version
  assertions now expect `20261004.01`; the new incoming room case exercises the current shape.
- Incoming room case passed once corrected to await the project's open-input acknowledgement;
  its initial failure incorrectly awaited a test-ready callback the fixture did not install.
- D2 database tests first failed on absent outgoing metadata and missing request-key uniqueness.
  A duplicate-token fixture collision was repaired before confirming the intended red failure.
- Additive migration stores nullable outcome and paired request-key/digest fields, a seven-value
  outcome constraint and a partial unique tenant/key index. PreparedCall storage preserves the
  fields and omits key/digest from Inspect. Database and codec group passed 23 tests, zero
  failures; an extra orphan-pair case was added for the new storage constraint.
- Both example JSON files now use incoming direction. A `mix run --no-start` check initially
  failed because the provider catalog was not initialized; normal `MIX_ENV=test mix run` parsed
  both successfully without contacting a provider.
- Compile with warnings as errors, strict Credo and unused dependencies passed. The first format
  check found one non-converged nested invocation layout; rerunning focused formatting corrected
  it, and the subsequent check passed. Final umbrella suite is in progress.

Twilio provisioning succeeded after the user created its compliance profile. All A–C resources
are now ready and a no-purchase repeat reports all found. The normal selected public Gateway
test passed 1 test with zero failures (seed 771983), then the test node/Funnel stopped. No carrier
call or paid AI/speech test has run during this checkpoint.

Remaining scope is unchanged: initial outgoing room/leg lifetime and first-message gating,
Gateway normal participant media, HTTP published-spec/idempotency workflow, inspection/outcome
times and the two-direction plus non-answer live acceptance. Root gates must pass before
marking this implementation checkpoint accepted. No commits requested or created.

## Accepted local checkpoint

The full umbrella suite completed successfully: 3,050 tests reported, zero failures,
98 excluded, seed 263210. All nine applications completed; Gateway's transfer/media
suite took 488.7 seconds and continued producing output throughout, so its elapsed
time was not treated as a stalled run. Final formatting, compile with warnings as
errors, strict Credo and unused dependency checks also passed. All three livetests
shell suites passed with fake providers. Documentation links and both updated JSON
examples were checked; `git diff --check` passed. D1 and D2 are accepted, while the
overall milestone/index remains unchecked. No live calls were placed.
