# Observability milestone plan

Date: 2026-09-08. Documentation-only checkpoint.

## Request and scope

Add the two requested vertical slices to the implementation plan: an observable sample
call early, and call inspection/debugging after asynchronous history. Keep descriptive
filenames; the index owns ordering. Phoenix adoption is still a separate discussion,
not approved by this request. No runtime migration or frontend implementation is included.

## Baseline findings

The architecture already lists operational timing, provider/queue/VM observations and
privacy requirements. Existing milestones cover private tool projections, persisted
history, usage/billing and later silent audio monitoring, but none delivers a dedicated
operational dashboard or a live/ended call inspection workflow. Those are distinct from
collecting billable usage or emitting events without a usable interface.

## Changes and rationale

- Added [Observable sample call](milestones/observable-sample-call.md) directly
  after the definition-driven call. Its end-to-end result is a sample conversation plus
  visible metrics and a controlled provider-failure scenario. It needs no persistence.
- Added [Call inspection and debugging](milestones/call-inspection-and-debugging.md)
  directly after asynchronous history, reusing tenant admission, variable and background
  tool work. Its result is a read-only operator workflow over live and persisted facts,
  including ended calls, permitted snapshots, timelines and honest archival gaps.
- The index now contains 23 specifications. All original milestone filenames and their
  relative order remain. Clarified the previously identified standalone MCP conformance
  exception without merging it or splitting other milestones in this task.
- Added a common gate for later slices to extend operational measurements/inspection,
  with safe metadata and a controlled failure/gap check. Final delivery also verifies
  opt-in diagnostic access and embedded telemetry independence.
- Linked the milestones from the architecture and clarified correlation versus metric
  labels. Authoritative call data, general metrics and UI caches are different concerns;
  observability does not create a second archival store or change retention.
- Preserved the voice console and existing protocol/process boundaries. A separate
  dashboard can use a separately approved Phoenix migration; this plan does not choose
  a framework or a new production authentication mechanism implicitly.

## Review and rejected scope expansions

Local design review checked runnable outcomes, direct prerequisite order, failure cases
and privacy/ownership constraints. No new review agent was used; historical approvals
are not attributed to these additions. Implementation boxes remain unchecked.

- Rejected waiting until billing/telephony to obtain basic operational visibility.
- Rejected treating metric emission alone as the runnable dashboard milestone.
- Kept payloads and high-cardinality identities out of general metric labels; retained
  restricted correlation and correctly sourced per-call timing where permitted.
- Checked the official Telemetry contract: handlers execute synchronously in the
  dispatching process. Bounded project-owned handlers cannot perform SQL/network or
  synchronous room work. Arbitrary embedding-host handlers are the host's responsibility.
- Kept operator inspection separate from caller tool visibility, agent variable grants
  and full VM introspection. Source-interval denials and secret exclusions still apply.
- Required explicit auth before external exposure without inventing browser API keys,
  a login product, new call scopes or automatic authorization from a tailnet URL.
- Deferred audio listening to the existing mixing slice. Added no recording, packet
  capture, tool execution/replay, variable editing, new persistence engine or tracing stack.

References: [Telemetry](https://hexdocs.pm/telemetry/telemetry.html#attach/4),
[LiveDashboard candidate](https://hexdocs.pm/phoenix_live_dashboard/Phoenix.LiveDashboard.html).

## Verification

- `git diff --check` passed.
- The index matches 23 distinct milestone files, numbered consecutively in the index
  only. The original 21 retain their relative order; all 40 direct prerequisite links
  point to earlier entries. No dependency cycle was introduced.
- All 98 relative file links and 33 heading links in the six changed/new documents
  resolve. Each milestone retains its expected outcome/specification/checklist/manual
  verification/review sections; implementation boxes remain unchecked.
- Architecture fenced examples are unchanged. Added documents contain no local absolute
  paths, credentials or prohibited labnote terminology.
- The first prerequisite checker misclassified a supporting decision-document link as
  a milestone dependency. Restricting that check to milestone links removed the false
  positive; no specification workaround was necessary.
- Reviewed the final scope/dependency diffs, including the delivery-stage access check.
  No application dependencies, call-definition schema, runtime code or UI changed.
  Runtime tests and browser inspection were not run for this specification-only change;
  both new milestones require those checks when implemented.
