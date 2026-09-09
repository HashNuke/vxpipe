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
  invocation and source-command references. Its Jido history entry retains private
  engine-origin metadata and produces no public caller event. The provider-facing
  chat role remains `user` because Gemini rejects a request ending after an assistant
  turn when the observation is projected as system context.
- Added per-LLM-call text tracking so buffered text accompanying a tool call is
  retained while an equivalent streamed completion is not emitted twice. Each
  LLM-message boundary flushes its residual sentence text.

Focused evidence:

- `mix test test/vxpipe/call_engine/agent_coordinator_test.exs test/vxpipe/call_engine/agent_request_transformer_test.exs test/vxpipe/call_engine/tool/dispatcher_background_test.exs`
  — 21 tests, 0 failures.
- Umbrella format, warnings-as-errors compile, default tests, and unused-dependency
  check passed after this checkpoint: Call Engine 157/0 (1 excluded), Gateway
  52/0 (4 excluded), Console 20/0.

### Room projection and runnable development Action

- Red: the focused room test failed because `RoomAuthority` did not handle the
  coordinator's continuation-start message. The delayed-report executor test
  separately failed while that production Action did not exist.
- `RoomAuthority` now tracks accepted background calls independently from the
  originating conversational turn. Interruption settles only unsent/active
  tool calls; an accepted call can report its one terminal result after the
  originating turn has completed or been interrupted.
- Engine-origin continuations create only an agent turn. They produce no fake
  participant turn or caller transcript event, while their agent output follows
  the normal sequenced text and optional speech path.
- Added the finite `prepare_background_report` Jido Action. It validates a
  short topic, bounds the requested delay to ten seconds, submits through the
  engine dispatcher, and returns a deterministic result.
- The trusted development definition exposes the Action with instructions that
  distinguish accepted/running from completed/ready. Its default delay remains
  two seconds.
- A real Jido test proves it can accept the supervised Action and finish the
  same conversational response while the worker is still blocked. Stopping the
  activation subtree then terminates that worker.

Focused evidence:

- `mix test test/vxpipe/call_engine/tool/executor_test.exs test/vxpipe/call_engine/agent_coordinator_test.exs test/vxpipe/call_engine/text_turn_test.exs`
  — 22 tests, 0 failures.

### Operational telemetry and provider interoperability

- Red: focused telemetry tests failed before the three background-tool events and
  Console aggregates existed. Added payload-free admission, local-worker stop, and
  completion-handoff events with bounded reservation/mailbox pressure. The Console
  reporter sanitizes them before mailbox entry and the existing diagnostics board now
  renders one compact background-tools instrument.
- Worker and coordinator tests cover accepted/saturated/start-failed admission,
  successful/unknown/terminated worker outcomes, and queued/consumed handoff. A
  reverse-order two-completion test proves both invocation identities are retained,
  duplicate delivery is ignored, and only one continuation runs at a time.
- The definition-driven room test now stops its receiver activation and proves the
  room-owned Call Variables process remains registered and readable; together with the
  worker-termination test this covers the subtree-lifetime boundary directly.
- A final sequencing audit found that the coordinator announced a continuation turn
  before asking Jido to admit it. A focused ordering assertion failed with the premature
  `continuation_started` message. The coordinator now announces the turn only after both
  request admission and dispatcher completion acknowledgement succeed, so admission
  failure cannot leave a phantom agent turn in RoomAuthority.
- The first full browser/provider run exposed a Gemini compatibility failure:
  `400 Requests ending with a model turn are not supported.` Projecting the private
  observation as system context had left the provider request ending in the prior
  assistant turn. The transformer now preserves Jido's provider-compatible user role
  and the private `vxpipe_origin: :engine` reference. RoomAuthority still creates no
  participant turn or caller transcript event.
- A tagged integration test now seeds an assistant turn and sends the private
  observation through the production transformer to Gemini
  `gemini-3.5-flash-lite`. It passes with `1 test, 0 failures` and returns non-empty
  model output.

Focused evidence:

- Call Engine background/room/telemetry set: `48 tests, 0 failures`.
- Console reporter and LiveView: `13 tests, 0 failures`.
- Gateway visibility/admission projection: `18 tests, 0 failures`.

### Rendered runnable outcome

- `bin/dev` served the React sample, gateway, RTVI transport, and diagnostics from
  the one Phoenix HTTPS listener at the Tailscale address on port 4000.
- In a full-visibility call, a typed request started a controlled ten-second queue
  report and received a running acknowledgement. A second typed “two plus two” turn
  was answered before completion. Its interruption stopped the stale acknowledgement
  playout; that audio did not resume. The report later produced exactly one ready
  response. The observed milestones were approximately 5.3 s, 6.0 s, and 11.4 s.
- The background diagnostics instrument showed an accepted admission, successful
  terminal duration, queued/consumed handoff, and bounded pressure. Empty and populated
  desktop (1440 px) and mobile (390 px) states had clear hierarchy and no horizontal
  overflow. `agent-browser` was not installed, so the same checks used headless Chromium
  and CDP; screenshots stayed under ignored `tmp/browser/`.
- Headless Chromium had no microphone input. This run verifies typed interruption,
  model text, audio playout, completion, and diagnostics, not live microphone capture.

### Final verification

The common root gates passed: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test`, and
`mix deps.unlock --check-unused`. The default suite covered Call Engine
`164 tests, 0 failures (2 excluded)`, Gateway `52 tests, 0 failures (4 excluded)`,
and Console `20 tests, 0 failures`.
