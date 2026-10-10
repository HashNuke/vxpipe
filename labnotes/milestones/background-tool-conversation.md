# Conversation during background tools

Status: complete as of 2026-09-09. Specification review: approved, including the
Jido ReAct/Action follow-up (2026-09-08).
Forward-runtime note (2026-09-10): Jido-specific mechanisms below remain historical
implementation evidence. The [ReqLLM agent-runtime milestone](reqllm-agent-runtime.md)
must reproduce the approved acknowledgement, cancellation, completion-mailbox and private
continuation behavior before Jido is removed. The subsequently selected
[tool execution model](../../docs/tool-execution-model.md) generalizes supervised submission to every
tool. This milestone's runnable conversation behavior becomes the explicit `non_blocking`
mode; bindings otherwise default to blocking later caller turns. The completed evidence below
still describes the implementation at the time it was collected.
Prerequisites: [Variables and tool projections](call-variables-and-tool-visibility.md).
Sources: [Asynchronous tools](../20260905-0405-call-definition-design.md#provider-independent-asynchronous-tools--approved-g4-decision); [timeouts](../20260905-0405-call-definition-design.md#mcp-timeouts-with-unconfirmed-outcomes--approved-g4-decision).

## Runnable outcome

A deterministic slow host tool starts during a call. The agent acknowledges it, answers another question while it runs, and later discusses its result in the current conversation without restarting interrupted speech.

## Specification

- Move submitted invocation execution out of the Jido ReAct run into bounded,
  independently supervised workers owned by that agent's subtree. Tool submission/access
  checks remain engine-owned.
- A submitted Jido Action validates its input and asks the engine to authorize and start
  that worker, then returns immediately. A successfully started invocation gets one correlated running
  acknowledgement as its ordinary tool response. Preserve accompanying assistant text in
  buffered and streaming adapter results without double delivery.
- Completion becomes a distinct invocation-linked engine observation, not a second ordinary
  result or old-turn replay. The per-agent coordinator retains it in a bounded in-memory
  mailbox until the matching live activation can consume it. If a Jido request is active,
  wait for its terminal event; when idle, submit one serialized internal continuation
  request with engine-origin provenance. Never rely on Jido `inject`/`steer` for delivery:
  those controls reject an idle agent and may drop queued input when an active run ends.
  The internal request is model context, not caller speech, and must not produce a public
  participant or transcript event. A chat provider may require this final non-model input
  to use its ordinary user wire role; private engine provenance, not that provider role,
  determines Vxpipe attribution. One agent coordinates output; no competing speaker or
  periodic automatic progress announcements.
- Speech/text interruption stops stale conversational output and unsent work, not an already-submitted invocation. Agent transfer/room shutdown terminates owned local workers; that is not remote rollback. A request already submitted to CallVariables can finish independently.
- Submitted timeout without definitive outcome reports unknown; pre-submission failure stays definite. No automatic executor retry for any failure, no tool read/write classification, durable worker, or explicit cancellation feature.
- Bound worker counts, queueing, deadlines, and result handoff; acknowledge only accepted work. Preserve invocation/turn/participant attribution and the existing visibility/private-event separation.
- Prove this slice with a finite static host Action using its declared name. The later
  [live-MCP bridge](remote-mcp-tools.md) submits remote bindings through these same workers
  and completion semantics; it does not move execution into Jido request-transformer or
  interceptor hooks or require a second model/tool loop.

Use this application-level workflow for every model provider, never a separate native-async
branch. A running acknowledgement is not business success. Completion remains untrusted tool
data: it neither updates Call Variables automatically nor authorizes interrupted unsent work.
Jido's ordinary ReAct loop may wait for completing actions; it must not wait for the lifetime
of a submitted action. ReAct cancellation stops the current conversational request, not the
already accepted Vxpipe worker.
The coordinator keeps exactly one ordinary or internal Jido request in flight. User input,
interruptions, and completion observations race through that queue with explicit activation
and request identities; an AgentServer busy rejection is handled as a coordinator invariant
failure, never by silently dropping or concurrently resubmitting an observation.

## Implementation checklist

- [x] Write red tests around a controllable slow tool, interruption, worker startup failure, timeout, and result ordering.
- [x] Split model-turn cancellation from submitted invocation lifetime and supervisor ownership.
- [x] Preserve mixed text/tool model results and encode Jido Action running acknowledgements
  plus later updates through the engine-owned Jido event adapter.
- [x] Integrate the bounded completion mailbox, terminal-event scheduling, engine-origin
  continuation requests, and private lifecycle facts for later archival.
- [x] Add tagged provider interoperability coverage; local context encoding alone is not evidence of provider acceptance.

## Acceptance and failure checks

- [x] Speak/type during submitted work: conversation proceeds, invocation finishes once, stale speech never resumes.
- [x] Fail worker startup: no running acknowledgement or fabricated business success.
- [x] Time out after submission: outcome unknown, no resubmission; keep a known definitive result if already received.
- [x] Kill agent subtree: local worker stops, room variables remain; no cancellation/rollback claim for remote work.
- [x] Multiple completions/out-of-order messages preserve identities and never produce duplicate ordinary tool results or competing TTS streams.
- [x] Deliver a completion while the Jido agent is idle and while a request is terminating:
  each is consumed once; no best-effort injection loss, fake public user message, or busy
  retry loop occurs.

Additional acceptance gates:

- [x] Buffered and streaming mixed text/tool responses deliver accompanying text exactly once.
- [x] Interrupted unsent tool work never submits; completion from a terminated agent cannot
  speak or attach itself to a replacement agent/activation.
- [x] Saturate bounded workers/queues: rejected work returns definite non-submission without
  a running acknowledgement; unrelated conversation and existing submitted work remain bounded.

## Manual verification

1. Bind a synthetic slow report tool and start a full-visibility debug call.
2. Invoke it, ask another question during the controlled wait, then release its result.
3. Confirm current-context discussion and exactly one invocation; repeat with an unknown timeout and a normal speech interruption.
4. Repeat with hidden tool visibility and verify conversation still works without lifecycle events sent to the browser.

## Scope boundaries

No remote MCP networking yet, explicit cancellation controls, automatic retries, durable invocation recovery, external webhook completion, or wait music. Business confirmation remains agent/application instructions.

## Completion and evidence

- [x] Demonstrate the runnable outcome and every acceptance/failure check above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence (2026-09-09): the implementation checkpoints introduced an
activation-owned bounded DynamicSupervisor, finite workers with absolute deadlines, correlated
running acknowledgements, and a dispatcher reservation that remains held until completion is
consumed. The agent coordinator now retains a bounded FIFO completion mailbox, serializes
caller and private continuation work, keeps accepted invocations alive across conversational
interruption, and fails its activation rather than silently dropping an impossible continuation.
It announces that continuation only after Jido admission and dispatcher acknowledgement, so a
failed invariant cannot leave a phantom room turn. The room projects completion through an
agent-only turn; it creates no participant turn or caller transcript. The finite
`prepare_background_report` Action makes the slice runnable.

Red/green tests cover accepted execution, saturation, startup failure, unknown timeout,
activation shutdown with room-owned variables still readable, mixed buffered/streaming text,
interrupted turns, completion while busy or idle, duplicate and reverse-order completions,
room attribution, and payload-free telemetry. The focused Call Engine run finished with
`48 tests, 0 failures`; Console telemetry and
LiveView coverage finished with `13 tests, 0 failures`; gateway hidden/full projection and
trusted-admission coverage finished with `18 tests, 0 failures`.

The tagged provider lane runs a scripted first turn followed by the actual Gemini
`gemini-3.5-flash-lite` provider and the production request transformer. It passed with
`1 test, 0 failures`, proving the provider accepts the engine-origin continuation after an
assistant turn. This coverage was added after a rendered end-to-end run exposed Gemini's
`400 Requests ending with a model turn are not supported` response when the continuation
had been changed to a system role. Retaining a provider-compatible user wire role while
preserving `vxpipe_origin: :engine` fixed that boundary without creating public caller speech.

Rendered verification used the single Phoenix HTTPS endpoint on Tailscale port 4000. The
full-visibility call started a controlled ten-second report, acknowledged it as running,
answered “two plus two” before the report finished, interrupted only stale playout, and later
produced exactly one ready response. The observed running acknowledgement, unrelated answer,
and completion arrived at approximately 5.3 s, 6.0 s, and 11.4 s respectively. The diagnostics
page showed worker reservation, completion-mailbox pressure, admission, terminal timing, and
handoff outcomes without payloads. Desktop 1440 px and mobile 390 px Chromium renders were
inspected in empty and populated states with no overflow or hierarchy defect. The requested
`agent-browser` executable was unavailable, so direct headless Chromium/CDP was used and that
substitution is recorded rather than claiming otherwise. Hidden lifecycle projection is
covered at the reusable gateway boundary.

Final umbrella evidence: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test`, and `mix deps.unlock --check-unused` passed.
The default test run covered Call Engine `164 tests, 0 failures (2 excluded)`, Gateway
`52 tests, 0 failures (4 excluded)`, and Console `20 tests, 0 failures`.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added provider-independent acknowledgement/result rules and mixed-output, stale-worker, unsent-work, saturation checks; re-review approved.
The 2026-09-08 Jido follow-up found that normal ReAct awaits completing actions and that
`inject`/`steer` is best-effort only for an active request. The corrected specification uses
a Vxpipe-owned bounded completion mailbox plus serialized, engine-origin continuation
requests. Focused source review approved this mechanism and its no-public-user-event gate.
This is specification evidence only; implementation and runtime verification remain unchecked.
