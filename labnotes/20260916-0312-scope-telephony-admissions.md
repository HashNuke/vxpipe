# Scope telephony admissions

## Boundary

- Continue from clean `68c0a95`; the previous turn made implementation progress and passed
  all root gates (1,575 tests, zero failures, 38 excluded).
- Carry the prepared entry service's canonical UUID alongside the alias in incoming claims
  and durable legs. Compare incoming provider/account identity before claiming a call.
- Scope duplicate queries, uniqueness and lifecycle lookup by tenant and canonical service.
  Preserve existing duplicate transaction/recovery behavior and initialized leg lifetimes.
- Keep historical rows unchanged: do not infer a service UUID by joining current aliases.
  Migration/legacy behavior was independently reviewed. Gateway live registry migration
  remains a separate unfinished reader boundary; this checkpoint cannot complete Telnyx alone.

## Red and implementation

- The seven new persistence tests ran before implementation: six failed for the expected missing
  isolation, account validation, duplicate identity, canonical field and historical rejection;
  the same-leg/new-event case already passed. Log: `tmp/telephony-identity-red.log`.
- Existing Twilio admission tests used a Telnyx service fixture. Enforcing provider/account
  identity exposed that incorrect setup. Completed the already planned Twilio storage prerequisite
  separately in `b6439ee`, then supplied actual Twilio-shaped fixture credentials here.
- Calls now checks claim identity against its pinned entry service. Persistence independently
  validates it before duplicate lookup and lifecycle writes. The durable uniqueness and query
  keys include tenant, canonical service UUID and provider.
- Duplicate matching includes account/control/leg/session, preserving the original claim for a
  new event ID on the same leg. It deliberately ignores newly generated call/participant IDs.
- Historical rows retain nullable service IDs. A scoped legacy event/leg collision rejects the
  new admission instead of adopting the alias or admitting a replay. Historical call inspection
  remains available. The migration does not add a service-retention foreign key.
- The first green attempt reached lifecycle persistence and exposed a test timestamp with no
  microsecond precision. Corrected the fixture to the existing `utc_datetime_usec` contract.
- The migration applied successfully to the test database. Eighteen focused tests pass, including
  the prior final-write lock and concurrent duplicate recovery tests with real connections.
  Calls passes all 84 tests. Logs: `tmp/telephony-identity-focused.log` and
  `tmp/telephony-identity-calls.log`.

## Restart and review

- A disposable database harness admitted two Telnyx and two Twilio tenant calls with matching
  aliases/provider IDs. A fresh VM read the stored plans before compiling definitions, resolved
  all four duplicates to their original tenant/service/call and updated each lifecycle separately.
  Both carriers retained their existing auth shape; no external provider request occurred.
  The harness removed its owned database. Log: `tmp/telephony-identity-restart.log`.
- Independent GPT 6 Astra xhigh review found no production blocker. Documented its rollout
  finding: stop old writers before migrating, because their nullable service IDs bypass the new
  uniqueness rules. Rollback can require resolving IDs that were valid only under tenant/service
  scope; it never deletes calls automatically. Mixed-version writing is unsupported.
- The reviewer also requested an explicit repository identity contract and a matching initial
  guard in the memory fixture. Both are implemented; bounded re-review found no remaining blocker.

## Checkpoint verification

- Full Persistence: 136 tests, zero failures, 11 excluded. Calls: 84 tests, zero failures;
  the six admission tests also pass after aligning the memory fixture's identity guard.
- The affected Gateway ingress and Telnyx/Twilio media-session group passes all nine tests.
- Root format, warnings-as-errors compilation, strict Credo and unused-lock checks pass.
  `git diff --check` and 182 relative documentation links/anchors pass.
- The full umbrella run follows this reviewed, focused checkpoint commit and will cover both
  the preceding Twilio storage slice and this identity slice. Current milestone progress stays
  at four of seven complete, three partial; Gateway readers and final platform cleanup remain.
