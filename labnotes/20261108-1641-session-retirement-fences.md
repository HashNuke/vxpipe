# Session retirement fences

Baseline: `dcc1fecc`. This checkpoint continues T1 with one batch-wide
retirement budget, final transport submission admission and non-renewing cleanup.
Participant composition, root renewal-job cancellation and catalog jobs remain
separate, unfinished milestone work.

## Design and reproductions

- Independent GPT-6 Astra xhigh design review approved reusing the idle startup
  guard as a lifecycle authority, rather than adding another permanent process.
  The guard must remain responsive and must not call ExMCP synchronously.
- Closing is monotonic. Every selected session is fenced before network cleanup;
  one absolute deadline bounds the whole batch. Cleanup gets an exact-session
  permission that cannot authorize ordinary POST/GET or a second DELETE.
- Supported stream socket workers must be direct transport-supervisor children.
  The owned default DNS lookup runs in the existing supervised resolver task;
  an additional linked Task would weaken the descendant termination barrier.
- Capture and monitor the transport supervisor before retirement. Integration
  DOWN alone is insufficient after forced death; orderly transport-supervisor
  shutdown acknowledges its direct child termination. Do not kill that supervisor.
- Calls cleanup-credential red: four tests, two missing-capability failures,
  seed 912301. Green including runtime credential regression: eight tests,
  zero failures, seed 554207. Near-expiry but still-valid tokens are usable;
  expired, claimed, disconnected and replaced grants never trigger renewal.
- MCP provider red: ten tests, two failures (six excluded). Provider green:
  ten tests, zero failures (six excluded), seed 283552.
- Transport-boundary red: eleven tests, two failures (six excluded), seed 438068.
  DELETE called ordinary resolution rather than the cleanup capability, including
  when the cleanup grant required reconnection. The checked patch must call the
  optional cleanup-header callback; Vxpipe fails closed when its trusted resolver
  lacks the non-renewing capability.
- Retirement integration red: six tests, six failures, seed 968925. Missing batch
  retirement/final fence and a stream socket outside the direct child tree were
  reproduced before implementation. First combined green: 23 tests, zero failures.
- Strengthened the final-fence assertion to require `not_submitted`: reproduced
  a locally rejected request being reported as `outcome_unknown`. Only the exact
  transport rejection is mapped to local non-submission; earlier admitted work
  retains ambiguous outcome handling.
- Existing regressions found lost per-client close telemetry and unconditional
  forced shutdown replacing ordinary shutdown. Both were corrected without
  changing the public telemetry or normal-stop contracts.

## Initial work state

At the first draft, lifecycle code, dependency patch regeneration, source review,
expanded wire acceptance and root gates were incomplete. The subsequent evidence
below records their progress; the latest gate status is authoritative.
No milestone acceptance checkbox is advanced by these partial results.

## Review corrections and expanded evidence

- Astra independently reproduced close returning success after client death while
  a suspended integration retained three transport children. The canonical case
  reproduces this before the fix. Description now retains the exact integration
  even without a live client registration; only verified current client PIDs may
  be signalled. A further controlled case waits for owner registry removal while
  the transport supervisor drains a slow child: old code returns early, corrected
  code waits for that exact transport barrier using its public identity metadata.
- Three suspended guards with a 30 ms deadline took 1,504 ms. Fence calls now use
  the remaining common deadline, and the local observation cap is also shared.
  Eight-case red: two failures; corrected lane: eight tests, zero failures.
- A get_headers-only provider reproduced ordinary credential resolution during
  owned DELETE. The regression ensures the module is loaded (otherwise an absent
  callback can accidentally make this test pass). Owned cleanup now skips that
  provider. Unowned library behavior is preserved. The 27-case combined lane passes.
- Added exact cleanup permission/single-use checks, rejection before new tool
  authorization, all-selected-session fencing before any cleanup callback, and
  another owner's continued invocation while DELETE is held. Twelve cases pass.
- Broader MCP integration/privacy/legacy/owned/telemetry lane: 101 tests, zero
  failures. Patch upgrades: nine cases pass, covering all four prior states;
  setup fixtures: 33 cases pass.
- Final review found legacy key close had lost its pre-client owner capture.
  The canonical runtime child-spec gate reproduces this without a debugger:
  eleven tests, one failure, seed 914396. Key close now captures the exact pending
  integration; local revoke also uses the batch retirement path. The combined
  retirement/connection/owned/telemetry lane passes 41 tests with zero failures.
- Graceful completion uses ordinary supervisor shutdown; expiry/failed cleanup
  forces the client/integration while preserving orderly transport child shutdown.
  Cleanup tasks themselves are bounded in case an alternate runtime ignores its
  callback timeout. No UI or speech/source-cutover state machine changed.

At that point, root gates and isolated preparation were still running. Acceptance
checkboxes stay open until their full contracts and final checks have evidence.

- Telemetry review reproduced missing close events on key-close/revoke and a
  repeated exact close incorrectly reporting closed instead of absent. Six-case
  red: three failures, seed 786627. All retirement entrypoints now report using
  their captured exact descriptions; the telemetry/connections lane passes
  17 tests, zero failures, seed 129825. These events feed the Console connection
  count; no UI component or UX workflow changes are needed.
- The first full-suite attempt was stopped after this reproduced runtime change.
  The corrected complete run was restarted; only completed runs supply the
  checkpoint gate evidence.

- The next umbrella run exposed an existing asynchronous metadata-I/O test missing
  its 100 ms callback acknowledgement while isolated setup was compiling. The
  same test passes in isolation with the failing seed 320149 (three tests, zero
  failures). Its setup and DOWN waits now use a bounded one second, matching the
  lifecycle lane; no production DiscoveryIO behavior changed. The suite was
  stopped after this known failure and will restart after setup finishes to reduce
  concurrent build contention. This is test scheduling evidence, not a change to
  the retirement grace budget or a runtime performance measurement.

## Next lifecycle work

T1 is still not complete. Reused-session credential resolution remains outside
its own bounded operation lifetime, so it must be fenced before renewal and tied
to the original opener/owner/deadline without retiring another valid user's
session. Complete startup/forced-owner and stalled-connect acceptance before
claiming the full standalone exit gate. Root renewal-job cancellation remains T3.

Read-only preparation for T2 confirms `AgentActivation.RuntimeGraph` currently
starts only `RemoteMCP.IntegrationOwner` as its MCP child; that binding process
still calls `connection_provider.open/2` and borrows the global session path.
The activation graph already supplies one-for-all recovery. Its new local host
must precede binding initialization, preserve that recovery policy, and have a
fresh PID after each recovery. `CatalogLoader` independently still uses open/2
and will require its own operation lifetime in T3. No Call Engine source changed
in this checkpoint.

## Checkpoint gate status

- Independent GPT-6 Astra xhigh runtime review has no remaining valid findings
  after the reproduced legacy-close and telemetry corrections.
- Final protocol/privacy/lifecycle lane: 105 tests, zero failures, seed 13405.
- Fresh-checkout `bin/setup` passes dev/test patched dependency compilation,
  frontend dependency/build steps and both isolated database migrations. The
  prepared checkout was then synchronized with the final telemetry/source changes;
  dev and test warnings-as-errors compilation both pass on that exact candidate.
- Root format, warnings-as-errors compilation, strict Credo and unused dependency
  checks pass. The final umbrella test run passes with seed 479143: 5,028 tests, zero
  failures, 310 excluded. Earlier interrupted attempts are not completion evidence.
- Patch/upgrade tests pass nine cases; setup fixtures pass 33. Changed Markdown
  links resolve locally, and staged whitespace checks pass. No lockfile changed.

The final staged evidence review is required before committing this checkpoint.
The overall milestone remains active.

- Full-suite seed 120884 exposed an additional telemetry race: Registry can still
  contain dead owners after teardown acknowledgements. It caused active counts
  to remain one and repeated close to report closed. A deterministic regression
  suspends registry cleanup after establishing a session and observes every owned
  process DOWN before querying close telemetry. Red: seven tests, two failures,
  seed 500535; the controlled case reports `{1, :closed}` instead of `{0, :absent}`.
  Counts now include only live registered owner PIDs. Retirement descriptions
  reject dead owners and dead remaining transport registrations, while still
  retaining a genuinely live transport subtree after integration death. The known
  failing umbrella run was stopped; it is not final gate evidence.

- Independent Astra review approves the registry-lag correction with no remaining
  source findings. Its isolated probes verify absent/zero for entirely dead trees
  and continued waiting/closed for a live transport subtree after integration
  death. The bounded DiscoveryIO test wait adjustment is also approved.
- The final corrected focused lane passes 45 tests. Root seed 479143 passes the
  complete umbrella, including the MCP application's 196 tests. Exact-candidate dev/test compilation in the
  prepared clean checkout also passes after the registry correction.

- Read-only preparation for the next checkpoint now has an isolated reproduction
  of reused-session authorization surviving a 100 ms deadline or host shutdown.
  The two-case probe fails both expected assertions (seed 364601); each callback
  remains blocked beyond the 500 ms observation bound. This is the already-open
  reused-credential lifetime gap, not a completed contract of this checkpoint.
  The existing owned-helper mechanism plus bounded caller-side admission is a
  candidate for containing the entire reuse authorization/readiness operation;
  preserve a valid existing session when only its new opener is cancelled.

- Closed two remaining T1 verification gaps without production changes: all twelve
  blocked authorization/DNS startup cases now keep a second actual ExMCP owner
  with the same credential key callable on its original wire session. Additional
  held-POST/active-GET cases kill the explicit host or exact integration and
  observe owned worker termination plus both peer socket closures. The combined
  startup/transport lane passes 35 tests, zero failures, seed 227780. This supports T1's owner
  isolation and forced transport-worker acceptance checkboxes; shared cleanup/
  remaining reused-credential and stalled-connect acceptance is still open.
  These tagged verification additions are excluded from the default umbrella lane
  and were run explicitly after its start; production sources were unchanged.

## Final checkpoint verification

- All five root gates pass: format, warnings-as-errors compilation, strict Credo,
  complete umbrella tests and unused dependency check. Completed umbrella result:
  5,028 tests, zero failures, 310 excluded, seed 479143. The two later tagged
  owner-death cases are outside that default run and pass in the explicit
  35-case startup/transport lane. No production source changed after the root run
  began. Lean is not applicable because no source-cutover/speech state machine changed.
- Fresh preparation, exact candidate compilation, four patch upgrades, protocol/
  privacy acceptance, corrected retirement/telemetry cases, local links and staged
  whitespace all pass as recorded above. No UI implementation changed.
- Independent GPT-6 Astra xhigh source review has no remaining valid findings and
  approves the two newly verified T1 checklist items. The full staged result and
  final gate evidence are submitted for the required pre-commit approval.
- T1 is now four of five implementation items complete. The remaining lifecycle
  item, T2, T3, T3b and T4 remain open: 25 of 29 implementation items are pending.
  This checkpoint does not claim participant placement, catalog jobs or whole
  milestone completion.
