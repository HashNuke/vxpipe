# Shared participant tool milestone

## Request and decisions

The user requested a progress-tracked milestone from the native STS tool research,
with common internal implementation and the same tool/MCP integration behavior
as LLM-based participants. Provider-specific implementation is excluded.

Created [Shared participant tool execution](milestones/shared-participant-tool-execution.md)
with four ordered checkpoints and 20 unchecked implementation tasks. Scope includes
shared descriptors/submission, native owned MCP activation, conversation/result
lifecycle and cross-path conformance/acceptance. Both conversation modes are
required; a blanket native non-blocking rejection cannot establish parity.

The common engine owns authority, execution, pending/completion state and business
policy. Provider sessions retain wire encoding and session mechanics. Native
single-result encoding remains distinct from the text loop's running/private
completion messages. This preserves protocol correctness without giving adapters
separate tool policies or promising unsupported semantics will work automatically.
Any missing semantic operation must be recorded against an unmet acceptance item;
it is not permission to silently weaken parity or expand into provider-specific work.

## Scope and dependency reconciliation

- Reused the existing tool executor/registry, tenant credential/catalog authority,
  participant-owned MCP implementation and semantic STS session boundary. No new
  agent framework, queue, schema, model policy table or provider integration.
- Read the milestone index, prior STS completion/lifecycle plans, tool execution
  model, ownership milestone and the current `STSProvider` callbacks, session
  commands, native tool event handling and text invocation submitter.
- Added the new milestone after completed participant MCP ownership and before
  delivery. The index now has 58 milestones, 45 complete and 13 incomplete. A
  structural count check caught the previously stale aggregate header; corrected
  the header to match the actual boxes without changing existing completion state.
- Transferred the older Package 1/common lifecycle work to the new progress owner;
  updated the parent and companions so historical boxes/proposals do not create
  duplicate tasks or imply an unfinished provider hosted gate blocks common work.
- Updated the research's earlier basic-only recommendation to reflect the user's
  stronger parity direction. Vendor findings remain useful protocol evidence;
  provider-specific extensions/live campaigns stay outside this milestone.

## Verification and review

Documentation-only planning; no runtime changes, deployment or new test execution.
Prior research's 34 passing tests and one defect reproduction are background
evidence only, not implementation progress for this milestone.

Structural checks pass: 20 unchecked tasks in four groups of five, sequential
index numbering/counts and all 16 links in the two new files. Whitespace checks
pass. No prior milestone completion checkbox was changed.

Independent review found one linked-source contradiction: the speech provider
contract still required the old text-style running acknowledgement and private
continuation receipts. Re-read its native tool section and confirmed that wording.
Corrected it narrowly to reference the new common-code/parity milestone, one final
native result and defined local acceptance/terminal discard with lease settlement.
The ownership, privacy, admission fencing and uncertain-outcome rules remain.
Review also requested a concise boundary clarification. Confirmed that native
result delivery targets a private call reference, history append only accepts
published caller/agent text, and capability hold may retire associations or close
the allocation. Added those constraints to prevent treating these APIs as an
already-working business hold/private completion path. No new task or adapter
implementation was added.

Independent re-review approved the specification with no remaining actionable
findings. Review approval is recorded separately from all 20 open implementation
tasks. Commit and push the documentation checkpoint under the standing instruction.
