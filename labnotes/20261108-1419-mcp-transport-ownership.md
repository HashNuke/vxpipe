# MCP transport ownership

Date: 2026-11-08. Baseline: `f0ad4f93` (committed and pushed).

## Reproductions before implementation

Continue T1 of the participant-owned MCP milestone after the exact-handle
retirement checkpoint. GPT-6 Astra xhigh source review identified unlinked
asynchronous POST workers, forgotten disconnect bookkeeping and normal-exit
stream lifetimes. The new tagged loopback tests now reproduce these gaps.

- Added a controlled HTTP fixture with a held asynchronous tool POST and an
  active standalone GET stream. It reports accepted requests and observes actual
  peer socket closure. No real credentials or third-party endpoint is used.
- The first four-case run failed at each POST worker termination assertion:
  session close, forced client death, normal client stop and explicit disconnect.
  Seed 334163; 4 tests, 4 failures. Initial failure cleanup unnecessarily waited
  for the fixture deadline; moving cleanup into `after` made the red lane bounded.
- Replaced spawn tracing with a fixture runtime-authorization acknowledgement of
  the actual POST worker PID. This observes the executing worker without assuming
  which process starts it, so future supervision changes keep the assertion useful.
- Added an independent idle-GET normal-stop case. Initial command, from
  `apps/vxpipe_mcp`: `mix test --include integration
  test/integration/session_transport_lifetime_test.exs`. Result: 5 tests, 5 expected
  failures, seed 879877, 5.3 seconds. Four POST workers lack DOWN after retirement;
  normal stop also leaves a linked stream/receiver descendant alive. No failure
  was an initialization, fixture, or protocol negotiation error.

## Review refinements and authoritative red evidence

- The reviewer found a fixture race: the asynchronous initialized notification
  could resolve authorization after open returned, so the probe could capture its
  PID instead of the held tool POST. A separate controlled reproduction confirmed
  the race. Wait for the fixture's initialized acknowledgement before enabling
  worker capture.
- Added stateless and GET-405 receiver cases. The first GET-405 attempt hit the
  default handshake timeout rather than the intended lifecycle assertion; set
  the fixture's handshake limit to 500 ms. Also corrected the worker probe to
  include recursive owned descendants and exclude shared Registry partition
  links. A shared registry partition must never be killed by test cleanup.
- Restored the exact preceding reviewed dependency sources and reran the corrected
  probe before applying the fix. Authoritative baseline: 7 tests, 7 expected
  lifecycle failures, seed 539802, 7.9 seconds. Four held POST workers survive
  retirement, the idle GET case retains a descendant, and stateless/GET-405 cases
  retain their receiver. These are the valid red results for the final probe.

## Implementation and decisions

- `IntegrationSupervisor` starts a dedicated, incarnation-named transport
  `DynamicSupervisor` before its client. Both are temporary/significant children.
  The checked ExMCP patch accepts a generic `:transport_supervisor` hook; Vxpipe
  supplies it after merging runtime options so a caller cannot override ownership.
  Resolve its name to the exact PID once. Missing ownership fails closed.
- POST, SSE and HTTP receiver tasks start through that supervisor. POST workers
  wait until the client has registered their monitor before doing network work.
  Transport-reference fencing rejects stale registration and task-reference fencing
  rejects late completion. Explicit disconnect/transport loss kills all workers
  before best-effort DELETE. The supervisor is dedicated to one client; sharing it
  would let one client's cleanup terminate another client's work and is unsupported.
- The supervised receiver is monitored rather than linked to the client. A new
  receiver-kill regression reproduced missing DOWN handling before its fix:
  8 tests, 1 failure, seed 508162. Handling that exact monitor now enters the
  existing transport-down path and cancels held POST work.
- Kept the pinned dependency revision and protocol profile. Extended the checked
  patch to ConnectionManager rather than replacing the transport. No dependency
  lockfile change is needed. Both previously supported patched states retain
  separately checksum-pinned upgrades; unknown/mixed modifications remain errors.
- Shell red tests first reproduced missing older-state recognition and ignored
  older-upgrade tampering: 9 tests, 2 failures. The patch tool now validates every
  declared upgrade and selects only an exact known source state.

## Verification and review

- Focused lifecycle lane: 8 tests, zero failures, seed 142165. It observes actual
  worker DOWN and held peer socket closure for session close, client kill/stop,
  disconnect and receiver death, plus idle GET and stateless/GET-rejected cleanup.
- MCP default suite: 172 tests, zero failures, 22 excluded, seed 613611.
- Expanded wire/security/privacy slice initially passed 22 tests, seed 917401;
  final rerun after the dead-supervisor fix passes 23, seed 466789.
- `bin/test-mcp-conformance`: both client-initialization and tools-call scenarios
  pass. `bin/test-mcp-sse-recovery`: all three scenarios pass. The pinned Everything
  reference lane discovers and executes echo successfully. No fixture revision or
  approved protocol profile changed.
- Patch application/upgrade suite: 9 tests pass, including pristine local clone,
  both supported upgrade sources and tampered upgrade rejection. Setup fixture
  tests also pass: 33 tests, zero failures.
  An initial combined `python3 -m unittest` invocation did not import this
  repository's non-package test directory; the documented direct script commands
  were used instead. This was a command error, not a product failure.
- GPT-6 Astra xhigh initial source review found no blocking runtime defect. Its
  documentation requests were to remove stale pre-implementation notes, make the
  dedicated-supervisor contract explicit and record the protocol/root evidence.
- Final review then reproduced an already-dead supervisor PID being accepted by
  the new generic ownership hook. `GenServer.whereis/1` returns a supplied PID
  unchanged, including after death. The stateless path reached ready and sent
  the initialized notification without needing a child start. Added the regression
  first: 9 tests, 1 failure, seed 281415. Startup now rejects dead/non-local supplied
  ownership before protocol initialization. Green: 9 tests, zero failures,
  seed 126723. Regenerated all checked patches and their hashes.
- Stopped the first umbrella test run to incorporate that verified review fix;
  its nonzero result was deliberate interruption, not a reported test failure.
  Format, compile and Credo had passed before interruption. Restarted affected
  protocol lanes and every root gate on the corrected sources.
- A clean local clone overlaid with the exact checkpoint runtime/test/patch files
  completed `bin/setup` successfully in 502.9 seconds. It reused no dependency,
  build, asset or environment directories. Preparation applied the patch, compiled
  the pinned dependency in dev and test, built assets and migrated both isolated
  databases. The clean build used two schedulers while the primary checkout's
  root suite ran; this duration is build evidence, not a runtime benchmark.
- All five final root gates pass: `mix format --check-formatted`, `mix compile
  --warnings-as-errors`, `mix credo --strict`, `mix test` and `mix deps.unlock
  --check-unused`. Umbrella tests: 5,002 tests, zero failures, 274 excluded,
  seed 614684, 750.7 seconds. The nine new lifecycle cases are in the separately
  passing tagged wire lane. No source-cutover or speech state machine changed,
  so Lean was not required. No UI changed.
- Relative documentation links and staged `git diff --check` pass. Final
  GPT-6 Astra xhigh review approved the exact 14-path staged checkpoint after
  inspecting the gate results; no valid findings remain.

T1 is still incomplete. These tests do not establish participant placement,
caller cancellation during blocked initialization, final submission fencing,
non-renewing cleanup, a single total cleanup budget, or exact renewal-job teardown.
Existing isolated checks bypass this hook and need their own regression coverage.
No complete call teardown, queued catalog maintenance or performance claim follows.
