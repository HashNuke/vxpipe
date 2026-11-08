# Call MCP lifetime

Baseline c94deca7 is clean, committed and pushed. This checkpoint continues the
connected startup, transfer and hangup behavior; no new coordinator is planned.

Two focused live-call tests reproduced blocked MCP initialization surviving both
hangup and preparation-task death (2 failures, seed 834903). Initialization now
runs in a linked temporary task. Its binding owner watches the room authority
while awaiting the bounded task, so cancellation releases the supervisor startup
stack. The final version uses the same linked helper for standalone and call use.
The first focused run passed 11 tests, seed 657948.

A transfer between two MCP-enabled agents exposed an existing mixed-tool bug:
IntegrationOwner accepted host tools but rejected the built-in transfer binding.
A focused unit test reproduced that failure; the binding owner now skips that
known non-MCP binding, leaving its validation to the existing tool compiler.
The real transfer test then reproduced a timed-out destination initializer staying
alive beyond the transfer deadline (seed 26498 first exposed the mixed binding;
its subsequent run reached the lifetime assertion).

A separate test reproduced MCP startup receiving a new five-second deadline
instead of the room's absolute readiness deadline (seed 520745). Startup and agent
transfer preparation now carry the existing absolute deadline and original
preparation PID. The existing RoomAuthority grants a fresh bounded recovery budget
only to its currently committed activation after startup readiness. Uncommitted
transfer destinations keep their original budget and preparation owner. No new
permanent process or participant-authority state machine is added.

An intermediate live-call and IntegrationOwner suite passed 15 tests, seed 118283.
It includes expired-original-budget recovery, held initialization cancellation,
transfer timeout preserving a usable source, pinned tool execution and leases.
The initialization task also bounds post-open handle validation with the same
budget.

Further tests reproduced normal second-integration failure and cancellation
leaving the first established session in a standalone host. Rollback now runs
after the opener stops and selects only the activation's keys under its exact host.
The normal close path uses one existing batch grace budget; it no longer gives
each integration the full readiness timeout.

Real protocol acceptance now covers two calls sharing a grant, cleanup of one
without changing the other, gated destination preparation before transfer commit,
re-entry with fresh local/remote identities, and harmless stale-handle closure.
Held POST and GET cases observe every selected session descendant terminate and
the peer sockets close on ordinary hangup and forced room-authority death.
The model fixture now correlates requests and waits for completed turns before
starting re-entry; responding to a retired source's queued model request or
interrupting an unfinished fixture response produced misleading test failures.

GPT-6 Astra xhigh reproduced four review findings before fixes:

- The binding owner also rejected supported platform tools. The focused
  mixed-binding test failed, then passed after skipping both known built-in types.
- A busy authority could turn a 100 ms startup budget into a 1,012 ms wait.
  The authority query now uses the same deadline/cancellation helper as opening.
  Separate tests cover deadline expiry and preparer death before any open.
  An admission probe also reproduced waiting on a suspended request supervisor;
  replacing supervised helper admission with direct linked tasks removes that
  boundary without adding a new runner or coordinator.
- A stalled source DELETE blocked RoomAuthority after transfer commit.
  Existing room-owned transfer tasks now perform exact source termination;
  the protocol regression checks input admission while DELETE is still held.
- Rollback could return while transport children drained after the integration's
  registration disappeared. It now discovers those exact parent/key transport
  registrations and uses the existing retirement completion barrier.

Independent review probes pass after the fixes: platform/budget 2 tests, seed
449054 (101 ms for the 100 ms deadline); remaining transport 1 test, seed 68921;
held DELETE responsiveness 1 test, seed 580272. The library rollback suite passes
17 tests, seed 265230.

The combined saved-runtime, transfer, boundaries, in-flight and telephony lane
passes 22 tests, seed 323044. It includes two admitted saved WebRTC calls and
client termination in all three phone admission paths. The synthetic restart
privacy case now waits for its authenticated initialization POST and open GET
before forcing a crash. Otherwise killing a DB borrower during startup could
abort the shared sandbox transaction and make replacement credentials disappear.
The fixture holds that stream to avoid unrelated reconnect reads during the
privacy assertion. No production credential fallback was added.

Final focused Call Engine checks pass 47 tests, seed 359346. Review noted that
the initial deadline case previously asserted propagation and then hung up;
it now actually expires a 500 ms readiness budget. The final live-call file
passes 15 tests, seed 159365, also including forced binding-owner death while
its linked initializer is held.

The full root suite (seed 217046) completed with four failures, all Gateway
handoff wait-mode variants. Each used the initialization task's PID as the
lasting binding owner. The test now releases that task but resolves readiness
through the destination activation's registered owner. Its audio/privacy/tool
assertions are unchanged. The focused rerun passes all four cases, 65 excluded,
on the same seed:

```shell
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs:1333 --seed 217046
```

No production code changed after the full run, so verification uses that run
plus the corrected cases rather than repeating every unaffected test. Root
format, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass. Astra source review accepts the fixture correction with no new
findings; final staged review approved this 24-file checkpoint. The milestone now marks
bounded startup/rollback and transfer overlap complete, leaving the broader
recovery/teardown and maintenance requirements open.

Safe embedded restart descriptors, exact root renewal cancellation, management
operation migration, durable catalog jobs and remaining acceptance/performance
work remain part of the full milestone.
