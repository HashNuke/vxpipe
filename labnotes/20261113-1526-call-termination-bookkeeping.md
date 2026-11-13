# Call termination bookkeeping

- Reviewed engine closure, incoming/outgoing carrier ownership, media subtree and
  WebSocket ownership, gateway cleanup tracking/retries and database projection.
- Live evidence: the test call had an archived `archive_stream_closed` and a
  terminal telephony usage observation, but no gateway cleanup completion. Its
  socket exited `:leg_unavailable` after `:media_session_not_found`.
- Root cause: handled socket failures used WebSock's abnormal process-exit path.
  The tracker consequently retained unknown cleanup even after transport close.
- Regression first: extended real Bandit WebSocket tests for both Telnyx/Twilio
  with invalid media and rejected leg dispatch. All four new cases failed with
  abnormal DOWN and unknown socket cleanup; original four cases passed.
- Fix: use normal WebSock stop while retaining error close codes 1008/1011.
  Preserve tracker crash/unknown rules, independent carrier proof, command
  drainage, usage persistence and incarnation-scoped database projection.
- Regression also proves that orderly socket close and room termination cannot
  persist completion before the carrier's separate acknowledgement and root DOWN.
- First green run exposed one test fixture assertion assuming the old observer-only
  fake-leg state; updated it for the fake leg's configurable result.
- Ownership review: the room owns archive closure; the carrier leg owns external
  termination, outstanding command drainage and final usage persistence; the
  media supervisor/socket own local termination. `CallCleanup` joins the exact
  roots and original-owner acknowledgements. Persistence joins that durable
  acknowledgement with archive closure under the call-row lock.
- Rejected marking ended from carrier events or room closure alone, or treating
  arbitrary abnormal DOWN as completion: these bypass independent obligations.
- Kept incident evidence in this labnote at the user's request. Added only the
  lasting contract to the existing call-runtime developer documentation.
- Focused validation: 54 Gateway and 19 Persistence tests pass, including the
  real local WebSocket regression. Format, compile with warnings-as-errors,
  strict Credo and unused-dependency checks pass.
- Deployed `vxpipe:cleanup-fix-20261113`; local and public health checks pass.
  The carrier had zero active calls before the service restart.
- Real SIP test: answered at 15:37:56 UTC, held 20 seconds and hung up normally.
  Database call state became `ended`; archive/ended timestamp 15:38:16.741051 UTC,
  cleanup completion 15:38:16.822949 UTC. No direct database edits were used.
- Telnyx independently confirms 20 connected seconds, `NORMAL_CLEARING`,
  completed/connected flags and zero remaining active calls.
- Broad suite found one more Twilio test probe asserting the retired abnormal
  exit reason. Updated its expectation while retaining close code 1008.
- Every other application suite passed in the full umbrella run. A concurrent
  Gateway rerun passed the changed assertion but hit an unchanged media test's
  100 ms acknowledgement timeout. Both affected test files pass alone (20 tests).
- A nonconcurrent Gateway run exposed another test setup issue: the MCP handler
  deadline test applied its 20 ms timeout to initialization, before the blocked
  operation under test. These test-only timing repairs belong to a separate
  verification commit. No runtime behavior changed for them.
- Focused timing verification passes (13 tests). Final nonconcurrent Gateway run:
  886 tests, zero failures (17 integration exclusions), 321.7 seconds. All other
  application suites passed in the umbrella run; all required static checks pass.
- Verified that all 13 changed production/configuration files match the deployed
  release snapshot. Later edits concern documentation and tests only.
- The two earlier test records still lack their historical cleanup proof; this
  change fixes new termination, rather than inventing lost tracker membership.
