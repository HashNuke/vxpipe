# Finish speech ownership

- Baseline: `f1e3d71`, adoption-authority repair verified and committed. Checkpoint R
  remains open; rooms continue using the legacy speech path.
- The next known R gap is operation deadlines. Three focused tests initially failed:
  held scope control caused close and failed-input cleanup to exceed a 35 ms budget;
  held Channel admission used the old 5-second timeout. Each lacked the required
  result within the generous 300 ms observation window. Tests resume held processes
  in `after` and await their jobs so failed experiments do not leave work running.
- The installed Task.Supervisor admission API can wait indefinitely before returning
  a task. Task.yield cannot bound that preceding wait. Astra review therefore
  recommended pulling the minimal persistent input worker forward from A4 into R.
  A4's broader input, usage and latency acceptance remains open.
- One temporary significant Input worker now belongs to each allocation. Channel
  admits one exact consumer/handle/ticket/deadline and remains responsive while the
  worker invokes the provider. Completion means synchronous provider acceptance;
  an independent Channel watchdog fences and retires timed-out work. Expired queued
  input is rejected without retiring an otherwise healthy allocation.
- A fourth red test held the local admission supervisor: Session.start returned
  `:unavailable` because ScopeControl itself blocked starting a Task. A persistent
  local Admission worker now receives casts from ScopeControl, retaining the two-slot
  reservation until admission completes. Blocking provider init stays below each
  allocation. Shared Admission failure follows the capability failure boundary.
- Two more red tests held either Channel or ScopeControl during adoption. Neither
  returned within the observation window. The API-entry operation deadline now
  travels through Channel and authoritative adoption; expired queued handoffs cannot
  commit, and a fresh adoption can still succeed before the original startup deadline.
- After these changes the 53 speech tests passed. Existing tests caught a changed
  post-retirement error (`:session_failed`); restored the established `:closed` result.
- Further review requested budget validation, rechecking time after input claim,
  safe provider-return normalization, and fencing before terminal replies. Work and
  verification are ongoing; no Exit R acceptance or load conclusion is recorded yet.
- Review identified two further deadline boundary races. Deterministic control debug
  barriers reproduced close returning `:ok` while a newly created tree's Channel
  remained held, and adoption delivering readiness after the public timeout. The
  close response now identifies the actual tree at authoritative cancellation;
  caller monitors that tree using the original remaining budget. Adoption has an
  atomic commit/abandon ticket shared through the API/controller; an uncertain
  committed handoff is fenced and retired, while a known uncommitted timeout can
  retry. Channel rechecks time before activating delivery, including direct startup.
  The speech group passed 67 tests after these changes.
- The first fault diagnostic runs exposed harness assumptions, not orphaned work:
  temporary capability children have already removed their ExUnit child entry after
  death, and Registry may briefly return the exact PID whose `:DOWN` was just
  observed. Removed redundant stop of the already-deleted child. Lookup assertions
  now allow only those exact observed-dead PIDs or nil, rejecting any new identity.
  Every owned provider/input/tree still requires its explicit `:DOWN`.
- The fault harness first passed 72 trials/39,360 healthy turns but blocked the
  coordinator while measuring replacement. Review correctly limited that claim.
  A second version performs failure/replacement in its own task and timestamps
  healthy PCM intervals. It passed another 72 trials/39,360 turns. Every 8/32-peer
  trial had replacement/input overlap (minimum 2/15 intervals); single-peer minimum
  was zero. Post-trial process count245 throughout, memory85.0–89.3MB. Both reports
  are retained; the concurrent report is the R evidence for continued healthy input.
- The unchanged latency diagnostic passed 68,400 turns. At 32 owners first-text p95
  was legacy2.133ms/native2.578ms, end1.526/1.567ms; held-native peer text2.229/end1.376.
  No overall speedup is claimed; the historical comparisons remain linked.
- Final review requested malformed ownership validation and a queued public reserve
  timeout test. The former reproduced nil-owner shared-control failure before the
  guard; invalid shapes now return invalid_configuration before reserving. Queued
  timeout token invalidation passed without a runtime change. All 70 speech tests pass.
- Adoption follow-up passed 16,236 turns across 36 trials. At 32 scopes adopted
  healthy-text/end p95: burst2.736/1.741ms, paced1.564/0.499ms. Old-lease close rejection
  p95.421/.277ms, current-consumer close2.072/.562ms. Process count245 every trial;
  memory86.1–89.7MB. No stale authority, PCM, event-order or monitored cleanup failure.
- Astra's final source review found no remaining R blocker, conditional on all root
  gates and final evidence. It required careful overlap wording and retaining the
  earlier failed global-prototype history. Root format, warnings-as-errors compile
  and strict Credo passed; the full umbrella suite is running, seed892574.
- A child-directory Credo attempt failed because that task is defined at the root;
  reran the required root command successfully. An early deadline test command was
  accidentally issued at the umbrella root; the owning child red reproduction was
  then run separately. Neither tooling mistake is recorded as runtime instability.
- Final umbrella verification: all five root gates passed; seed892574. Per-app
  tests: MCP37, Agent95, CallEngine770, Calls117, Gateway460, Artifacts20,
  Persistence184, Console185. Total1,868 tests, zero failures, 40 excluded.
  Gateway took357.8s and CallEngine79.6s; no implementation changes were made while
  awaiting those gates. Marked R accepted (1/9); A4 and room migration stay pending.
- Changed Markdown local links and git diff whitespace checks passed. The standalone
  README example ran verbatim successfully with MIX_ENV=test mix run; startup,
  independent PCM input, semantic acknowledgements and close all completed.
