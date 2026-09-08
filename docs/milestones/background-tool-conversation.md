# Conversation during background tools

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Variables and tool projections](call-variables-and-tool-visibility.md).
Sources: [Background tools](../../labnotes/20260905-0405-call-definition-design.md#provider-independent-background-tools--approved-g4-decision); [timeouts](../../labnotes/20260905-0405-call-definition-design.md#mcp-timeouts-with-unconfirmed-outcomes--approved-g4-decision).

## Runnable outcome

A deterministic slow host tool starts during a call. The agent acknowledges it, answers another question while it runs, and later discusses its result in the current conversation without restarting interrupted speech.

## Specification

- Move submitted invocation execution out of the model-turn task into bounded, independently supervised workers owned by that agent's subtree. Tool submission/access checks remain engine-owned.
- A successfully started invocation gets one correlated running acknowledgement as its ordinary tool response. Preserve accompanying assistant text in buffered and streaming adapter results without double delivery.
- Completion becomes a distinct invocation-linked update to the latest conversation, not a second ordinary result or old-turn replay. One agent coordinates output; no competing speaker or periodic automatic progress announcements.
- Speech/text interruption stops stale conversational output and unsent work, not an already-submitted invocation. Agent transfer/room shutdown terminates owned local workers; that is not remote rollback. A request already submitted to CallVariables can finish independently.
- Submitted timeout without definitive outcome reports unknown; pre-submission failure stays definite. No automatic executor retry for any failure, no tool read/write classification, durable worker, or explicit cancellation feature.
- Bound worker counts, queueing, deadlines, and result handoff; acknowledge only accepted work. Preserve invocation/turn/participant attribution and the existing visibility/private-event separation.

Use this application-level workflow for every model provider, never a separate native-async
branch. A running acknowledgement is not business success. Completion remains untrusted tool
data: it neither updates Call Variables automatically nor authorizes interrupted unsent work.

## Implementation checklist

- [ ] Write red tests around a controllable slow tool, interruption, worker startup failure, timeout, and result ordering.
- [ ] Split model-turn cancellation from submitted invocation lifetime and supervisor ownership.
- [ ] Preserve mixed text/tool model results and encode running acknowledgements plus later updates across supported adapters.
- [ ] Integrate latest-conversation completion scheduling and private lifecycle facts for later archival.
- [ ] Add tagged provider interoperability coverage; local context encoding alone is not evidence of provider acceptance.

## Acceptance and failure checks

- [ ] Speak/type during submitted work: conversation proceeds, invocation finishes once, stale speech never resumes.
- [ ] Fail worker startup: no running acknowledgement or fabricated business success.
- [ ] Time out after submission: outcome unknown, no resubmission; keep a known definitive result if already received.
- [ ] Kill agent subtree: local worker stops, room variables remain; no cancellation/rollback claim for remote work.
- [ ] Multiple completions/out-of-order messages preserve identities and never produce duplicate ordinary tool results or competing TTS streams.

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
This is specification evidence only; implementation and runtime verification remain unchecked.
