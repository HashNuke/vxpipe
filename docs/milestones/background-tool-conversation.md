# Conversation during background tools

Status: not implemented. Specification review: approved, including the Jido
ReAct/Action follow-up (2026-09-08).
Prerequisites: [Variables and tool projections](call-variables-and-tool-visibility.md).
Sources: [Background tools](../../labnotes/20260905-0405-call-definition-design.md#provider-independent-background-tools--approved-g4-decision); [timeouts](../../labnotes/20260905-0405-call-definition-design.md#mcp-timeouts-with-unconfirmed-outcomes--approved-g4-decision).

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
  The internal request is model context, not caller speech, and must not be projected as a
  user message or public transcript event. One agent coordinates output; no competing
  speaker or periodic automatic progress announcements.
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

- [ ] Write red tests around a controllable slow tool, interruption, worker startup failure, timeout, and result ordering.
- [ ] Split model-turn cancellation from submitted invocation lifetime and supervisor ownership.
- [ ] Preserve mixed text/tool model results and encode Jido Action running acknowledgements
  plus later updates through the engine-owned Jido event adapter.
- [ ] Integrate the bounded completion mailbox, terminal-event scheduling, engine-origin
  continuation requests, and private lifecycle facts for later archival.
- [ ] Add tagged provider interoperability coverage; local context encoding alone is not evidence of provider acceptance.

## Acceptance and failure checks

- [ ] Speak/type during submitted work: conversation proceeds, invocation finishes once, stale speech never resumes.
- [ ] Fail worker startup: no running acknowledgement or fabricated business success.
- [ ] Time out after submission: outcome unknown, no resubmission; keep a known definitive result if already received.
- [ ] Kill agent subtree: local worker stops, room variables remain; no cancellation/rollback claim for remote work.
- [ ] Multiple completions/out-of-order messages preserve identities and never produce duplicate ordinary tool results or competing TTS streams.
- [ ] Deliver a completion while the Jido agent is idle and while a request is terminating:
  each is consumed once; no best-effort injection loss, fake public user message, or busy
  retry loop occurs.

Additional acceptance gates:

- [ ] Buffered and streaming mixed text/tool responses deliver accompanying text exactly once.
- [ ] Interrupted unsent tool work never submits; completion from a terminated agent cannot
  speak or attach itself to a replacement agent/activation.
- [ ] Saturate bounded workers/queues: rejected work returns definite non-submission without
  a running acknowledgement; unrelated conversation and existing submitted work remain bounded.

## Manual verification

1. Bind a synthetic slow report tool and start a full-visibility debug call.
2. Invoke it, ask another question during the controlled wait, then release its result.
3. Confirm current-context discussion and exactly one invocation; repeat with an unknown timeout and a normal speech interruption.
4. Repeat with hidden tool visibility and verify conversation still works without lifecycle events sent to the browser.

## Scope boundaries

No remote MCP networking yet, explicit cancellation controls, automatic retries, durable invocation recovery, external webhook completion, or wait music. Business confirmation remains agent/application instructions.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_c on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Added provider-independent acknowledgement/result rules and mixed-output, stale-worker, unsent-work, saturation checks; re-review approved.
The 2026-09-08 Jido follow-up found that normal ReAct awaits completing actions and that
`inject`/`steer` is best-effort only for an active request. The corrected specification uses
a Vxpipe-owned bounded completion mailbox plus serialized, engine-origin continuation
requests. Focused source review approved this mechanism and its no-public-user-event gate.
This is specification evidence only; implementation and runtime verification remain unchecked.
