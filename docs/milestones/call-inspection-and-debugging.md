# Call inspection and debugging

Status: in progress. Persisted inspection reads and the engine-owned bounded live
projection are implemented; the Console workflow and browser operator-auth boundary
remain. Scope requested by the user; specification reviewed locally on 2026-09-08.
Browser operator authentication must be selected before external exposure.
Prerequisites: [Observable sample call](observable-sample-call.md);
[Asynchronous history](asynchronous-call-history.md), including its tenant admission,
Call Variables and background-tool prerequisites.
Sources: [Security and observability](../architecture.md#security-and-observability);
[Gateway/console boundary](../gateway-console-boundary.md);
[History ownership](asynchronous-call-history.md); [Variables and private tool projections](call-variables-and-tool-visibility.md).

## Runnable outcome

An authorized operator selects a call in a separate inspection page, follows its
participant/turn/tool timeline, examines permitted variable snapshots and available
timings, and identifies a controlled tool failure or delayed archive write. After the
call ends, the same page remains useful from stored history without a live room process.

## Specification

- Provide a read-only call list/detail workflow beside the sample and operational
  dashboard, not controls overlaid on the voice console. Start with a bounded list
  and paginated history; loading, empty, unavailable, denied and ended-call states
  are real outcomes rather than endless spinners or fabricated empty histories.
- The Phoenix `vxpipe_console` / `Vxpipe.Console` application owns these pages and their
  browser access boundary, using Calls public APIs for history and gateway/engine public
  interfaces for permitted live projections. The reusable gateway authenticates/translates
  call API/protocol requests; it does not gain Phoenix or dashboard dependencies.
  Calls owns authorized persisted-history reads through persistence ports; the engine
  owns explicitly projected live facts. Do not query Repo from the console or gateway,
  read arbitrary process state or subscribe browsers directly to unrestricted internal
  messages. No new source of truth for call history.
- Scope every list, detail and subscription to the trusted operator principal and tenant.
  Reuse established authorization boundaries; neither a public call ID nor a participant
  join token grants inspection. Keep application-wide VM diagnostics separate from
  tenant-scoped call data. Choose/document the browser authentication mechanism before
  non-development exposure; never place tenant API keys in frontend configuration/storage.
  A restricted synthetic development fixture is not production login or authorization.
- Show existing facts: participant/activation identity and lifecycle, accepted input and
  generated/delivered/interrupted output distinctions, turn and invocation identity,
  safe tool status plus permitted arguments/results, variable revisions/snapshots and
  available correlated timings. Source time/order matters; receipt order does not prove
  causality. Missing metrics, unknown tool outcomes and incomplete events remain explicit.
- Reuse the early telemetry definitions for units and boundaries. Preserve available
  per-call timing facts through the existing permitted archival path where needed for
  ended-call inspection; do not reconstruct exact timings from aggregate charts or make
  general metrics the transcript/tool database. Mark unsupported earlier history unavailable.
- Keep live accepted state and persisted state distinct. A latest archived variable
  revision can lag the room's accepted revision. Show each source/revision honestly;
  never present a later live snapshot as the value at an earlier tool event. Inspection
  must not make variable success or ongoing conversation wait for SQL.
- Authorized operator history is distinct from ordinary client `tool_visibility`.
  Hidden client tools can remain inspectable through separately authorized history reads;
  showing them here must not elevate the caller's event policy. Existing transcript/media
  denials and credential exclusions apply before queueing and when projecting results.
  Do not expose private execution handles, credentials or forbidden payloads even in
  full-debug mode. Render remote tool content as untrusted data without executing HTML,
  auto-fetching resource links or introducing document-inspection features.
- Live updates use bounded project-owned read/subscription boundaries. Detect duplicate
  IDs and gaps using available provenance; page reconnection may resubscribe/read retained
  facts, but never resumes an ended call, executes tools, replays speech or joins a room.
  Disconnect/slow consumers cannot accumulate unbounded room or browser queues.
- Show persisted facts while a live owner is unavailable, and distinguish database outage,
  collecting/lagging data and known loss from successful empty results. Page, read-port or
  subscriber failure cannot restart or block the call. Opening inspection does not start
  STT, recording or any participant capability.
- Reuse call-owned archival retention; inspection is not an independent unlimited cache
  or export store. Later retention deletion removes access to the history, and stale
  subscriptions/caches must not republish purged records. This slice adds no purge job.

## Implementation checklist

- [ ] Specify the bounded list/detail/live projections and operator-auth boundary using
  existing trusted identity and history contracts; do not invent new call scopes in the UI.
- [ ] Red-test cross-tenant/unauthorized access, private projections, pagination, event
  correlation, snapshot revisions and live-versus-persisted source labeling.
- [ ] Add any missing permitted per-call timing facts to the existing asynchronous
  archival projection without changing general metric labels or making writes synchronous.
- [ ] Implement console-owned read-only pages and bounded updates through public APIs,
  with explicit stale/gap/error states and no UI dependency in the reusable gateway.
- [ ] Exercise delayed storage, failed/unknown tool outcomes and terminated rooms through
  deterministic fixtures; keep hosted-provider/network checks in the integration lane.
- [ ] Inspect desktop/mobile list/detail views and verify the voice console stays unchanged.
- [ ] Document the operator workflow, access limits and differences from caller visibility.

## Acceptance and failure checks

- [ ] A variable update and slow host tool appear on their original participant/turn/
  invocation timeline with the correct snapshot revision and observed outcome.
- [ ] An ended call is inspectable with no room PID; absent timing/history is explicitly
  unavailable/incomplete rather than invented from current state or aggregates.
- [ ] Delay/fail storage during a live call: ongoing conversation and variable acceptance
  continue; live and persisted revisions/lag are distinguishable in the page.
- [ ] Another tenant, ordinary caller or forged call identifier cannot read or subscribe
  to private data. Hidden caller events remain hidden while authorized operator history works.
- [ ] Credential/forbidden-content sentinels do not reach responses, UI caches or logs;
  remote HTML/resource links cannot execute or trigger automatic fetches.
- [ ] Paginated, duplicate/out-of-order and interrupted subscriptions retain bounded
  state and honest gaps; reconnect never creates a call, executes a tool or replays audio.
- [ ] Missing, denied, unavailable and purged-call responses are safe; stale cached facts
  cannot recreate deleted history. A closed page releases subscriptions without ending calls.
- [ ] No console/gateway-to-Repo dependency, gateway-to-Phoenix/UI dependency,
  unrestricted process inspection or additional media capture is introduced. General
  VM visibility is never implied by tenant authorization.

## Manual verification

1. Start a synthetic call with a permitted prefilled variable and controlled slow host tool.
   Open the authorized inspection page separately from the voice console.
2. Read/update variables, submit the tool, speak while it runs, then release or time out
   the fixture. Inspect the correlated timeline, snapshots and available timings.
3. Pause archival writes; verify live/persisted distinctions while the call continues.
   Restore storage and inspect only retained facts, without a lossless-recovery claim.
4. End the call, stop its room tree and reopen history. Try another tenant and an
   ordinary caller token; verify no private call data is disclosed.
5. Disconnect/reopen inspection, exercise large paginated history and unavailable data,
   and check desktop/mobile states. Confirm no participant or audio stream was added.

## Scope boundaries

No audio listening/recording/playback, new retention engine, exports, arbitrary tool
execution/cancellation, variable editing, process-control console, provider billing
implementation, historical call replay, tenant administration UI or production login
product. Silent audio monitoring remains in [live mixing/media policy](live-mixing-and-media-policy.md).
Later provider/transfer/storage slices extend the inspector for their implemented facts.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and all acceptance/failure checks above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, index entry, architecture/user docs and implementation labnote
  with actual authorization, fault-injection, focused-test and rendered-browser evidence.

Implementation evidence to date:

- `vxpipe_calls` owns tenant-authorized, cursor-bounded call summaries and persisted
  detail pages, one correlated fact/variable timeline, latest persisted revision, and
  explicit archive closure/gap/duplicate metadata. Its Ecto adapter selects only the
  bounded fields and records needed by those contracts.
- Each planned room incarnation now owns an engine-local live inspection buffer. Its
  producer port rejects excess work instead of blocking room processes; the default
  limits are 64 pending and 256 retained records. The buffer receives the same
  policy-filtered private facts as archival storage plus accepted Call Variables
  baselines/updates, including when archival storage is disabled.
- The live buffer is a non-significant temporary child. If it fails, inspection becomes
  unavailable rather than restarting with fabricated continuity, while the room and its
  participants continue. Its snapshot hides retained private records from `Inspect`.

The Console pages, operator browser authorization, Calls-owned live translation, rendered
browser verification and end-to-end fault fixtures are still incomplete; this evidence
does not complete the milestone.

## Specification review

Local design review on 2026-09-08 checked history/admission prerequisites, a useful
live-and-ended call workflow, tenant isolation, independent client visibility, interval
privacy, read-only ownership, bounded subscribers and honest archive lag. It kept audio
monitoring in its existing milestone and operator authentication explicit before exposure.
The subsequent approved console/gateway boundary received a focused specification review:
the earlier observable-call slice supplies the Phoenix shell, inspection uses public
Calls/live-projection interfaces, and browser authorization remains separate from API-key
and caller-token admission. No new prerequisite or tenant administration UI is implied.
This is specification evidence only; implementation and browser checks remain unchecked.
