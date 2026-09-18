# Automatic tool retries and business idempotency

Status: deferred for later review. No automatic retry policy, tool classification
layer, or business-idempotency exception is approved for the initial executor.
This issue carries R16 and the future extensions to the R14/R15 baseline.

## Current baseline

The tool/MCP executor does not automatically retry failed invocations, including
failures known to occur before submission. Return the observed result/error to
the agent. A submitted request whose remote outcome is unconfirmed at timeout
reports `unknown`, not definite failure or rollback; retain a definitive result
when already known.

A later agent-requested tool call is a distinct invocation. This distinction
does not guarantee exactly-once execution or prevent the agent from requesting
the same external action again. Do not add trusted read-only/idempotent-write/
side-effect categories as a prerequisite now.

For example, a booking may exist remotely even though its response never arrives.
The current executor returns unknown and does not resubmit it. If a tool is
rejected before submission, return that definite error without an automatic retry
as well. The agent can reason about the outcome and request another invocation;
that is not a hidden executor attempt.

## Questions to revisit

- Which failures, if any, should permit automatic retry, including known
  non-submission versus ambiguous submission outcomes?
- What explicit provider/business idempotency contract would make another
  attempt safe? Request-correlation IDs do not by themselves deduplicate a
  business operation. Decide key ownership, scope, lifetime, and reuse with
  changed arguments against the actual external contract.
- Is trusted operation classification useful, and what evidence supports it?
  A category label alone does not prove a side effect can safely be repeated.
- How should one invocation relate to multiple attempts, and how should attempt
  identity, observations, timing, and final outcomes be recorded without hiding
  uncertainty or reporting a request-start event as success?
- What bounded retry budget, deadline/backoff, and lifecycle behavior should
  apply if retries are later approved? How would transfer/shutdown interact
  without inventing remote rollback guarantees?
- Should explicit business-idempotency support permit a narrowly scoped retry
  exception, and how would missing/unsupported guarantees fail safely?

These are future review questions, not configuration fields, provider adapters,
retry loops, reconciliation jobs, or durable-operation requirements for this slice.

## Scope boundaries

This deferral concerns tool/MCP executor retries. Call-creation idempotency (R39)
and admission crash recovery (R40) remain separate pending decisions; they are
not deferred by this issue. Normal database transaction behavior is unchanged:
variable-update success waits for the snapshot/pointer transaction to commit,
and a transaction error is a save failure. No extra commit-status reconciliation
or new variable retry workflow is introduced.

Ordinary speech interruption, agent/room shutdown, explicit-cancellation deferral,
and late external-event deferral keep their existing contracts. Business-side
deduplication and validation remain the external system's responsibility, not
Call Variables acting as that system's transaction database.

## Future verification

If a retry policy is later approved, use deterministic adapters to distinguish
known non-submission, remote commit with lost reply, duplicate attempts, changed
arguments, and exhausted budgets. Verify the provider's actual idempotency
contract in a separate integration lane before promising duplicate prevention.
For now, planned tests only prove the approved no-automatic-retry baseline and
distinct later invocations. No runtime changes or tests were made for this issue.

Related: [call-spec design](../../labnotes/20260905-0405-call-definition-design.md),
[architecture](../architecture.md), and [G4 review](../call-spec-gap-review.md#g4--p1-partly-resolved-tool-cancellation-does-not-roll-back-an-external-action).
