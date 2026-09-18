# Explicit cancellation of background tool calls

Status: deferred for later review. The proposal below is not approved for
implementation or inclusion in the call-spec schema.

## Problem and example

A user asks an agent to generate a report. The agent starts a background tool
invocation and continues the conversation. The user then says, "Never mind the
report." Stopping speech alone does not stop that invocation; merely saying it
was cancelled is not an execution operation.

The approved application-level background workflow separates invocation lifetime
from model/speech turns. That makes targeted local cancellation possible, but
does not decide when it should be offered or how the agent requests it.

## Candidate approach to revisit

- Tools explicitly opt in with a setting such as `cancellable: true`, defaulting
  to false. The name and placement of this setting are proposals, not schema.
- Expose a generated tool such as `cancel_<tool>` for eligible tools. Target an
  identified running invocation, not every invocation of the same tool.
- Stop that invocation's local worker without stopping the agent's conversation.
- Prevent results arriving after local cancellation from re-entering the
  conversation. Decide completion/cancellation races explicitly; do not erase
  an already-known outcome or claim completed work never happened.
- Report local invocation cancellation separately from the remote action's
  outcome. Local termination does not establish remote cancellation or rollback.

Cancelling a pending `create_booking` invocation is not the same operation as
cancelling an existing booking. The latter requires the external system's actual
booking-cancellation tool. The agent must not claim a booking was cancelled just
because Vxpipe stopped waiting for a response.

## Open decisions

- Whether to adopt the opt-in policy and generated-tool interface at all.
- Where cancellation eligibility lives in trusted tool configuration.
- Target selection when several invocations run, name collisions, and handling
  requests against completed, unknown, or ineligible invocations.
- Completion races, result suppression, and the acknowledgement presented to the
  model and authorized event consumers.
- Whether a remote MCP cancellation notification is attempted where supported;
  such a request would still not guarantee that a business action was undone.

## Scope retained while deferred

Do not require a generic cancellation tool, new configuration option, or its
implementation tests for the current slice. Ordinary speech/text interruption
still does not express tool-cancellation intent. The approved agent-lifetime,
transfer/shutdown, deadline, unknown-outcome, and no-automatic-retry contracts
remain unchanged. This issue does not introduce durable jobs, remote rollback,
or recovery of an invocation after agent shutdown.

If this proposal is adopted later, verify targeted cancellation with deterministic
worker barriers and monitors, including multiple invocations, continued
conversation, completion races, and no false claims about remote outcomes.
Live MCP cancellation interoperability would need separate integration checks.
No runtime behavior has been implemented or tested for this proposal.

Related: [call-spec design](../../labnotes/20260905-0405-call-definition-design.md),
[architecture](../architecture.md), and [G4 review](../call-spec-gap-review.md#g4--p1-partly-resolved-tool-cancellation-does-not-roll-back-an-external-action).
