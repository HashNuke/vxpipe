# Bounded session startup

Baseline: `e511f2d2`. This T1 checkpoint bounds new-session initialization by the
opening caller, exact host owner and one absolute monotonic deadline. It does not
complete activation composition, final submission fencing or graceful retirement.

## Reproductions and decision

- The isolated real-ExMCP probe reproduced clients surviving both opener and host
  death while authorization was blocked: two tests, two failures, seed 308423.
- The canonical tagged startup lane then reproduced authorization and DNS stalls
  under caller death, normal host stop, host death, exact integration death and
  deadline expiry. It also rejected the current behavior of accepting an already
  expired deadline. Result: 12 tests, 11 expected failures, seed 639558. The control
  case (opener exit after successful readiness) passes.
- Independent GPT-6 Astra xhigh design review recommended opt-in deferred ExMCP
  initialization and ordinary exit propagation for our supervised HTTP profile.
  The client must acknowledge startup before arbitrary authorization or network
  callbacks, so supervisors can finish without waiting for them. Linked handshake/DNS helpers must become supervised,
  monitored work before removing client exit trapping.
- A startup guard begins before the client and watches opener, host and absolute
  deadline. Readiness publication must acknowledge the guard before disarming it;
  this includes reuse and public lookup. Cancellation targets the exact integration
  PID and cannot affect a replacement.
- Rejected an additional client-binding lifetime worker that keeps exit trapping:
  it creates binding and shutdown-order races and a second termination mechanism.
  A callback-only cleanup cannot handle forced death.

## Verification

- Initial implementation passes 37 focused startup/owned/legacy connection tests,
  seed 498177. Existing transport-only disconnect/receiver-loss assertions also
  counted the newly idle startup guard; they now exclude that exact PID in those
  two cases, while complete session/client retirement still monitors every child.
- Reproduced loss of an insignificant guard leaving blocked initialization alive:
  14 tests, two failures, seed 4321. The guard is now a significant temporary
  child and stays idle after readiness; losing it retires the integration.
- Extended DNS coverage observes both the wrapper and linked resolver task DOWN
  after host death or DNS timeout. Immediate successful resolution and recovery
  of an established session after a failed DNS helper also pass. The DNS startup
  cancellation tests use a 30-second resolver timeout so the shorter startup
  deadline, rather than DNS timeout, must perform cancellation.
- Startup lane: 17 tests, zero failures, seed 808680. Combined startup/transport/
  legacy/owned boundary slice: 52 tests, zero failures, seed 375720.
- Astra reproduced admission before the startup guard exists: an open with a
  25 ms deadline stayed blocked after 300 ms behind a suspended host. The same
  queued request could begin client initialization after expiry; a controlled
  scheduling pause reproduced real authorization at that point. Canonical
  delayed-host regressions fail before the fix: 20 tests, two failures,
  seed 800625. An initial test cleanup attempted to disable tracing after killing
  the traced process; moving that step before cancellation fixes the test itself.
- Start-child now uses a linked, bounded task with the original opener and
  absolute deadline captured before the task starts. Timeout kills and drains
  that task. Guard initialization synchronously rejects an expired deadline or
  dead opener before later children may start, so a queued abandoned request
  cannot initialize a late client.
- Astra also reproduced a new DNS-wrapper lifetime gap: killing a POST during
  DNS removed the requester that enforced its timeout, leaving the wrapper alive
  until session close. Its isolated probe supplied the initial reproduction.
  The first canonical fixture could select an initialized-notification DNS task
  while killing a later tool POST; it now awaits both initialized notification
  and initial GET before enabling the controlled stall.
- Each owned synchronous helper now has a temporary passive watcher under the
  transport supervisor. The result task is nontrapping, links to that watcher,
  and runs only after both caller monitor installation and watcher acknowledgement.
  The watcher independently monitors requester/deadline; a tagged abnormal exit
  terminates the result task and linked DNS descendants. The task handle monitors
  the actual result sender, preserving result-before-DOWN ordering. A temporary
  supervisor per helper was rejected as unnecessary overhead; one watcher and
  one result task suffice. Direct ExMCP users without owned supervision keep the
  existing behavior.
- Tests observe watcher, result task and nested DNS task DOWN on requester death,
  watcher death and expiry with the requesting POST suspended. The same established
  session remains callable. The corrected startup lane passes 21 tests,
  seed 888312; expanded focused lifecycle tests pass 58, seed 478134. Independent
  reviewer probes confirm both original findings are fixed, with no remaining
  runtime findings before final gates/staged review.
- Final protocol/privacy lane passes 57 tests, seed 647718, including official
  conformance, corrected SSE recovery, Everything and management-check regressions.
  Patch tests pass nine cases covering all three supported prior states; setup
  fixtures pass 33. The direct Python script commands are required; a combined
  unittest module invocation cannot import this repository's non-package tests.
- Root format, warnings-as-errors compilation and strict Credo pass on corrected
  sources. The first full-suite run was deliberately interrupted to incorporate
  the admission fix. The corrected full suite and clean-checkout preparation are
  running. The clean clone needs `--no-hardlinks` across filesystem boundaries;
  the first default local clone failed before setup, then a fresh clone with
  copied Git objects started normally.

The completed previous checkpoint's disposable checkout and this clean build
exceeded the local temporary-files quota. Setup failed while preparing frontend
dependencies; the simultaneous umbrella test command also exited without a
complete summary. Removed only that earlier generated checkout, preserving its
external evidence logs, then reran setup in the new checkout and restarted the
full umbrella tests with adequate free space. No dependency/build/asset/environment
directories were shared with the primary checkout.

Focused commands from `apps/vxpipe_mcp`:

```shell
mix test --include integration test/integration/session_startup_lifetime_test.exs test/integration/session_transport_lifetime_test.exs test/vxpipe/mcp/connections_test.exs test/vxpipe/mcp/owned_connections_test.exs
mix test --include integration test/integration test/vxpipe/mcp/runtime_auth_privacy_test.exs test/vxpipe/mcp/runtime_auth_provider_test.exs
```

Preparation commands from the umbrella root:

```shell
bin/patch-ex-mcp
python3 test/shell/ex_mcp_patch_test.py
python3 test/shell/setup_test.py
```

The disposable clean checkout runs `bin/setup` with two BEAM schedulers while the
primary checkout runs its root suite. This is preparation evidence, not a runtime
performance benchmark. No UI or source-cutover/speech state machine changed.

- Clean-checkout `bin/setup` now completes successfully: patched dependency dev
  and test builds, frontend dependencies/assets and both isolated database
  migrations pass. The primary checkout's compiled runtime files were not reused.
- The DNS deadline test gives the outer tool request five seconds while DNS has
  one second, ensuring the request timeout cannot mask watcher behavior. This is
  a test-only timing refinement; its final startup lane passes 23 tests,
  seed 287709. Runtime source and the 58-test combined/57-test protocol evidence
  remain unchanged.

The default new-session startup deadline is five seconds; an absolute monotonic
deadline may be supplied and is never reset inside that session. Reused-session
authorization is still caller-side work and has not gained its own bounded
lifetime in this checkpoint. Root-owned renewal cancellation, the final transport
submission fence and common graceful cleanup budget remain unfinished.

## Final verification

- All five root gates pass on the corrected runtime: format, warnings-as-errors
  compilation, strict Credo, umbrella tests and unused dependency check. The
  completed full suite reports 5,017 tests, zero failures, 298 excluded,
  seed 670311. Its separately run integration lanes are recorded above.
- Clean-checkout preparation and all supported patch upgrades pass. Relative
  documentation links, staged whitespace and local-path checks pass. No lockfile
  change is needed: the dependency revision remains unchanged.
- Independent GPT-6 Astra xhigh reviews approved the staged runtime and later
  documentation/test refinements, with no remaining findings. Final gate evidence
  is submitted for the pre-commit review.

T1 remains incomplete. No participant placement, activation-wide grace budget,
complete teardown acknowledgement, catalog maintenance, call acceptance or runtime
performance completion is claimed by this checkpoint.
