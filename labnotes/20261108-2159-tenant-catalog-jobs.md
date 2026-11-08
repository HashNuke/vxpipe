# Tenant catalog refresh jobs

The existing tenant connection row already owns the discovered catalog. Static
save and successful OAuth completion populate it; manual refresh also exists.
This checkpoint adds the approved freshness timestamps and durable maintenance,
reusing the existing Repo, isolated ConnectionCheck and OAuth grant coordination.

The embedded-restart checkpoint's full umbrella run is still running on fixed
source. Initial freshness regressions are prepared outside the checkout so that
this next checkpoint does not change the running suite's input. No catalog
implementation has been written yet.

Official Oban documentation was rechecked on 2026-11-08. The current package is
2.24.2; it provides `cron`, `lifeline` and `pruner` configuration directly. Use the
existing approved two-worker design. Uniqueness applies at insertion and can
return a successful conflict result; row locking and conditional publication
remain Vxpipe-owned contracts. Sources:
[package](https://hex.pm/packages/oban),
[cron](https://oban.hexdocs.pm/Oban.Cron.html),
[lifeline](https://oban.hexdocs.pm/Oban.Lifeline.html),
[pruner](https://oban.hexdocs.pm/Oban.Pruner.html),
[uniqueness](https://oban.hexdocs.pm/unique_jobs.html).

Headless execution can reuse MCP.ConnectionCheck directly. The saved OAuth
protocol adapter currently lives in Console; move its reusable implementation
to a lower owning application, preserving Calls' existing durable claim workflow.
No browser principal, Console dependency, custom queue or additional runtime
coordinator is needed.

The first focused database regressions fail for the intended missing behavior:
static initial save and successful OAuth completion both lack `refreshed_at`.
Two tests, two expected failures, seed 319143. The temporary test and log are
`vxpipe-mcp-catalog-freshness-red.exs` and `vxpipe-mcp-catalog-freshness-red.log`;
move the test into the persistence owner application before implementation.

The focused publication contract now also covers competing results and a backward
clock. Its four-test red run has four expected failures, seed 36915: the two missing
timestamps and the absent guarded publication entry point. The planned repository
call adds an explicit expected freshness/scheduling pair; it does not add another
revision field. Manual and queued callers will use that same conditional write.

The preceding embedded-restart checkpoint passed all five root checks (5,077
tests, zero failures, 344 excluded, seed 296639), received exact staged Astra
approval and was committed/pushed as `84863bb6`. Its source stayed fixed during
that run. A push notification records the updated milestone count, 14 of 29.

The freshness test now lives in the persistence application. The migration adds
nullable microsecond timestamps and a connected-row due index without inventing
freshness for old rows. Initial saves/replacements set successful freshness and
clear obsolete scheduling. Conditional publication compares both observed fields
under the existing row lock and advances at least one microsecond; manual refresh
passes its original snapshot guard. These four focused tests pass, seed 428655;
the owner persistence/save/renewal lane passes 38 tests, seed 521546.

The Oban lockfile resolves 2.24.2 without changing other dependency versions;
its PostgreSQL schema migration is pinned to version 14. Three scheduling tests
first fail for the absent adapter, then pass with the five headless workflow
tests (seed 482144). Two configuration tests first fail, seed 669458, then the
queue/freshness/configuration lane passes nine tests, seed 219114. Calls' catalog,
credential and manual-management lane passes 29 tests, seed 534398.

Two thin workers delegate to Calls, using standard Oban uniqueness/retries and
finite timeouts. The metadata query excludes incomplete matching jobs before
the batch limit and uses JSON containment compatible with Oban's existing args
index. Insertion and scheduling timestamp commit under the same connection-row
lock and Repo transaction; a successful uniqueness conflict does not update time.
Application configuration supplies expiry, suppression, batch size, cron, queue
concurrency, timeouts, Lifeline and pruning. No environment variables were added.

The existing OAuth protocol adapter moved from Console to Calls, and generic
token-request projection moved to MCP. Its existing tests moved with ownership;
thirteen combined OAuth/workflow cases pass, seed 652397. Discovery uses the
existing ConnectionCheck protocol through a host-configurable module/options
port; its focused red proves the previously ignored port, and all six workflow
cases pass afterward, seed 781860. The library's lifecycle was not rewritten.

Early independent Astra source review reports no concrete defect in the current
draft; that is not a completion review. Actual queued execution, obsolete manual
refresh, redacted failure, cancellation and worker timeout pass five real database
and HTTP cases, seed 941443. They observe held POST closure and supervised process
termination. Four independent-database scheduling cases pass, seed 353611:
concurrent sweepers, an actual Oban uniqueness conflict held through its telemetry
boundary, enqueue rejection, and failure after job insertion but before timestamp
publication. Both failure directions roll back the job/timestamp pair.

Held/stale/duplicate publication and lifetime checks now pass with the freshness
and OAuth boundary tests: 28 tests, seed 68946. Actual tenant-isolated execution
passes eleven tests, seed 366157. The independent scheduling/node file passes five
tests, seed 231842. Its first two attempts exposed a fixture setup error, not a
production failure: the synthetic peer had not loaded the Persistence application
specification, so Oban could not resolve its worker module. Loading that existing
application specification fixes the fixture without starting a second Repo.
The successful replacement-BEAM case kills the executing node, observes peer
socket closure, then rescues the same durable job on attempt two through Lifeline.

The saved-call case executes an MCP tool while discovery is held, publishes a
changed catalog, and verifies the live model retains its original tool schemas
and exact session. A second held refresh survives authorized API hangup and
publishes after the saved call reaches durable `ended` state. The first attempts
used the lower-level room teardown helper, then an admission without managed
cleanup; those fixture paths do not provide durable API completion. Enabling the
existing managed-cleanup option and monitoring its tracker supplies the correct
boundary. The final case passes, seed 341925. It verifies text/tool responsiveness,
not audio-flow acceptance; the latter remains open.

The final Persistence lane passes 62 tests, zero failures, seed 740152. Its bounded
backlog has twelve connections, batch size five and queue concurrency four:
enqueue counts are 5/5/2/0; all twelve jobs finish on their first attempt in
1,075 ms from queue startup. Existing Oban telemetry reports queue delays of
1,045,432–1,094,408 microseconds and execution durations of 13,327–19,037
microseconds. All twelve DELETEs are observed; discovery sessions return to the
baseline of zero. These are local controlled-peer measurements, not production
capacity claims. The actual protocol fixture rejects execution inside a Repo
transaction, including on the independent BEAM. Replacement explicitly clears
old scheduling and records its fresh initial snapshot.

The final Calls workflow/manual-refresh/OAuth lane passes 38 tests, seed 631102.
Independent Astra source review approves the expanded checkpoint with no concrete
correctness or unnecessary-complexity finding. Final Console regressions, root
gates and staged evidence review remain pending; T3b's audio-flow gate stays open.

The Console saved-call/phone/transfer/OAuth lane ran 47 tests, seed 541494. Three
machine-OAuth assertions compared an unchanged connection against the snapshot
captured before a successful manual refresh; the newly tracked `refreshed_at`
correctly advances. The corrected tests require only freshness to change at that
refresh and require a failed replacement to preserve its subsequent exact snapshot.
All nine tests in that affected file pass on the same seed; no production fix was
needed. The other 38 cases passed in the combined run. Root format, compile with
warnings as errors, strict Credo and unused-dependency checks pass. The full
umbrella test run now uses fixed source and is being observed through one handle.

The remaining audio check reuses the existing managed-phone fixture: hold a real
catalog response, run a spoken turn, observe all five 20 ms carrier audio frames,
then release discovery and observe successful publication. This passes as a
focused external test, seed 108040, and is added as a tagged Console integration
case while the root run remains on unchanged production source. No additional
speech, queue or transport implementation is required. The separate WebRTC case
supplies durable-hangup/maintenance independence evidence.

An initial version combined the audio probe with `SavedMCPTelephonyCase.close/2`.
Its existing assertion that gateway cleanup time cannot precede archive-derived
end time fails twice, seed 108040, although the carrier output and durable ended
state were observed. The focused audio case uses ordinary room cleanup; timestamp
ordering remains a T4 phone-acceptance question. Do not treat this as a catalog
production fix or silently change end-state projection in this checkpoint.

The canonical two-case Console call/audio lane passes, seed 569388. Independent
Astra incremental review approves both cases and the corrected OAuth assertions,
and confirms that all eight T3b items have evidence pending the final root gates.
The four fast root checks pass again after the tagged audio case was added.

The single full umbrella run completes successfully: 5,094 tests, zero failures,
363 excluded, seed 412417. Together with the explicit tagged lanes, all five root
gates pass. The milestone and index now record T3b's eight items complete, bringing
implementation to 22/29. The remaining seven items concern T3 credential/late-result
composition and T4 lifecycle, performance, privacy and final/manual acceptance.
Final staged Astra review approves all 59 explicit paths (53 entries after rename
detection), verifies the counts/local links, and reports no outstanding finding.
The checkpoint is ready for the requested commit and push.
