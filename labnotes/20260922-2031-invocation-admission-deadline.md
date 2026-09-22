# Invocation admission deadline

Parent approved the P2 repair after independent review of `96fb0395`. Privacy
repair is separately committed as `1e1ac9f2`; preserve both checkpoints.

## Design review before tests/code

Registry submit and reconciliation each wait one second. Checking admission
only before DynamicSupervisor.start_child allows an already-entered preparation
to resume after both callers have returned unavailable, then execute a tool.
The existing owning test suspends Registry itself and misses this window.

Reproduce at the compiled STS room and owning registry boundaries by suspending
InvocationSupervisor and tracing Registry's actual outgoing start_child request.
Wait for unavailable before resuming in after; then assert no host_started,
no record and no prepared child. A second owning check must cover begin queueing.

Carry the one original absolute admission deadline from submit through Registry
preparation and into Invocation's begin handling. Registry checks again after
preparation; Invocation checks on begin receipt before Task creation. Never
renew the deadline. Reject and clean up prepared workers if expiry wins; retain
the existing accepted-work execution budget and outcome semantics.

Minimal proposed generic write set: InvocationRegistry admission helpers,
InvocationSupervisor.begin_invocation deadline forwarding, and Invocation.begin
deadline-aware admission. Existing direct begin callers retain their current
API; no startup/private-handle or provider changes. The milestone task list and
this separate design review were recorded before red tests or runtime edits.

## Red/green evidence

Run from the isolated owning `apps/vxpipe_call_engine` directory with local
copied build/dependencies. No root, native, load, hosted or billable commands.

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/room_authority/sts_tool_lifecycle_test.exs test/vxpipe/call_engine/tool/invocation_registry_test.exs test/vxpipe/call_engine/tool/invocation_supervisor_test.exs --seed 0
```

Red execution 58158, terminal exit 2: 26 tests, three failures. Both suspended
preparation tests observe the outgoing Registry start_child call and then await
caller-visible unavailable before resuming. Both returned a running invocation
record after resumption, reproducing the review finding. The queued-begin test
failed because the deadline-carrying begin API did not exist.

Runtime fix threads the same submit deadline through Registry's helpers,
rechecks after preparation and forwards it through begin_invocation/2 and
Invocation.begin/2. Worker-side admission checks before creating the action
Task. Existing one-argument begin behavior is preserved. The registry's existing
error path demonitor/terminate cleanup handles expired prepared workers; no
record, usage or accepted lifecycle publication is added for them.

Green execution 17011, terminal exit 0: all 26 tests pass. Tests require empty
registry snapshot and supervisor child list, with no host-start message after
resumption. The queued begin remains task/timer-free after caller timeout and
resumption; its prepared worker is then explicitly stopped and monitored DOWN.

Final approved group, execution 10258, terminal exit 0: 102 tests, zero failures:

```sh
ERL_FLAGS='+S 2:2' mix test test/vxpipe/call_engine/room_authority/sts_tool_lifecycle_test.exs test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs test/vxpipe/call_engine/capability/speech_to_speech_test.exs test/vxpipe/call_engine/tool/invocation_redaction_test.exs test/vxpipe/call_engine/tool/invocation_supervisor_test.exs test/vxpipe/call_engine/tool/invocation_registry_test.exs --seed 0
```

## Local review

No admission deadline is renewed and no execution-timeout/outcome/reconciliation
logic changes. Prepared-worker startup options/private handles are untouched;
only deadline-aware begin forwarding/admission was added to those two modules.
Source/epoch/tool IDs and provider contracts are unchanged. Exact edited files
are formatted; diff whitespace checks pass. Parent owns independent review and
root/integration acceptance. Running acknowledgement, private completion commit
and blocking/nonblocking admission remain OPEN.
