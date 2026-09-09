# Background tool runtime

## Goal

Implement milestone 5, conversation during background tools, without moving the
model/tool loop out of Jido or treating caller interruption as cancellation of an
already accepted invocation.

## Checkpoints

### Bounded activation-owned execution

- Red: `mix test test/vxpipe/call_engine/tool/dispatcher_background_test.exs`
  failed because `BackgroundSupervisor`, `Dispatcher.submit/4`, and completion
  acknowledgement did not exist.
- Added an explicitly marked `:background` tool execution mode. Inline tools and
  Call Variables keep their existing synchronous behavior.
- Added an activation-owned dynamic supervisor and temporary invocation workers.
  A worker executes outside both the dispatcher and Jido request process, applies
  an absolute local timeout, and reports a bounded result back to the dispatcher.
- The dispatcher reserves capacity until the coordinator acknowledges consuming
  a completion. It returns a correlated `running` acknowledgement only after the
  worker starts. Saturation and worker-start failure return definite errors.
- A timeout after accepted submission reports `{:error, :unknown}` and does not
  retry the action.

Evidence:

- `mix test test/vxpipe/call_engine/tool/dispatcher_background_test.exs test/vxpipe/call_engine/agent_activation_supervisor_test.exs`
  — 5 tests, 0 failures.
- `mix test` from `apps/vxpipe_call_engine` — 152 tests, 0 failures, 1 excluded.
- Umbrella gate: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test`, and `mix deps.unlock --check-unused` all passed. The umbrella test
  run covered Call Engine 154/0 (1 excluded), Gateway 52/0 (4 excluded), and
  Console 20/0.

This checkpoint provides the execution primitive only. No configured Action uses
it yet, and coordinator mailbox/continuation behavior remains to be implemented.

### Serialized completion handoff

- Red: a focused coordinator test failed because no internal continuation command
  or completion mailbox existed. A request-transformer test separately proved
  that Jido initially projected the completion input as caller-role content.
- `AgentCoordinator` now recognizes a private running acknowledgement only when
  the dispatcher has the corresponding reserved invocation. It emits acceptance,
  retains completions in a bounded FIFO mailbox, prioritizes queued caller work,
  and starts one internal continuation only after Jido is idle.
- Caller interruption cancels and discards the active conversational request but
  leaves accepted background work and queued completion observations intact. A
  stale terminal event cannot revive interrupted output.
- The continuation carries a fresh command/request identity plus the original
  invocation and source-command references. The request transformer projects its
  Jido history entry as system context based on private engine-origin metadata;
  it is not caller speech.
- Added per-LLM-call text tracking so buffered text accompanying a tool call is
  retained while an equivalent streamed completion is not emitted twice. Each
  LLM-message boundary flushes its residual sentence text.

Focused evidence:

- `mix test test/vxpipe/call_engine/agent_coordinator_test.exs test/vxpipe/call_engine/agent_request_transformer_test.exs test/vxpipe/call_engine/tool/dispatcher_background_test.exs`
  — 21 tests, 0 failures.
- Umbrella format, warnings-as-errors compile, default tests, and unused-dependency
  check passed after this checkpoint: Call Engine 157/0 (1 excluded), Gateway
  52/0 (4 excluded), Console 20/0.

RoomAuthority does not consume the new acceptance/continuation messages yet, and
the development definition still exposes no background Action. Those are the
next integration checkpoint.
