# Call inspection and debugging

Status: complete. Persisted inspection reads, the engine-owned bounded live
projection, and the Console's authenticated list/detail workflow are implemented and
browser-verified. A deterministic end-to-end call proves conversation, tools, variables,
live inspection, and later archive drain through a storage outage. The acceptance checks
and common implementation gates have passed. Scope requested by the user; specification
reviewed locally on 2026-09-08 and completed on 2026-09-09.
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

- [x] Specify the bounded list/detail/live projections and operator-auth boundary using
  existing trusted identity and history contracts; do not invent new call scopes in the UI.
- [x] Red-test cross-tenant/unauthorized access, private projections, pagination, event
  correlation, snapshot revisions and live-versus-persisted source labeling.
- [x] Add any missing permitted per-call timing facts to the existing asynchronous
  archival projection without changing general metric labels or making writes synchronous.
- [x] Implement console-owned read-only pages and bounded updates through public APIs,
  with explicit stale/gap/error states and no UI dependency in the reusable gateway.
- [x] Exercise delayed storage, failed/unknown tool outcomes and terminated rooms through
  deterministic fixtures; keep hosted-provider/network checks in the integration lane.
- [x] Inspect desktop/mobile list/detail views and verify the voice console stays unchanged.
- [x] Document the operator workflow, access limits and differences from caller visibility.

## Acceptance and failure checks

- [x] A variable update and slow host tool appear on their original participant/turn/
  invocation timeline with the correct snapshot revision and observed outcome.
- [x] An ended call is inspectable with no room PID; absent timing/history is explicitly
  unavailable/incomplete rather than invented from current state or aggregates.
- [x] Delay/fail storage during a live call: ongoing conversation and variable acceptance
  continue; live and persisted revisions/lag are distinguishable in the page.
- [x] Another tenant, ordinary caller or forged call identifier cannot read or subscribe
  to private data. Hidden caller events remain hidden while authorized operator history works.
- [x] Credential/forbidden-content sentinels do not reach responses, UI caches or logs;
  remote HTML/resource links cannot execute or trigger automatic fetches.
- [x] Paginated, duplicate/out-of-order and interrupted subscriptions retain bounded
  state and honest gaps; reconnect never creates a call, executes a tool or replays audio.
- [x] Missing, denied, unavailable and purged-call responses are safe; stale cached facts
  cannot recreate deleted history. A closed page releases subscriptions without ending calls.
- [x] No console/gateway-to-Repo dependency, gateway-to-Phoenix/UI dependency,
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

- [x] Demonstrate the runnable outcome and all acceptance/failure checks above.
- [x] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [x] Update this milestone, index entry, architecture/user docs and implementation labnote
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
- `Calls.inspect_live_call/3` is the tenant authorization boundary above that engine
  source. It requires the established `:calls` scope, validates snapshot and per-record
  call identities, converts engine records into Calls-owned values, and returns only a
  correlated timeline explicitly labeled `live` plus bounded loss/revision metadata.
  Ecto archival writes reuse the same engine-to-Calls projection.
- Console operator authentication reuses a tenant API key with the existing `:calls`
  scope. The API-key secret is submitted to the server for authentication but is never
  serialized into the browser session. The signed session carries only tenant/API-key
  identifiers, closed scopes, and a one-hour expiry; malformed, wrong-scope, and expired
  identities fail closed. Authentication dispatch is replaceable at the Console boundary,
  while the production adapter delegates credential verification to the public Calls API.
- Console now has one inspection read boundary for list, persisted-detail, and live-detail
  projections. Its production adapter calls only public Calls APIs, configured adapter
  options take precedence over per-page cursor/limit options, and unexpected adapter values
  fail closed before reaching a page. The replaceable boundary supports deterministic
  Console fixtures without adding Repo or engine-private access to the presentation app.
- `/operator/sign-in` now exchanges an existing tenant key and `:calls`-scoped API key for
  the non-secret signed browser session. `/calls` and `/calls/:call_id` are the only routes
  behind that guard; the sample, diagnostics and LiveDashboard remain outside it. Phoenix
  request filtering removes API-key values from debug request logs.
- The Console loads at most 25 call summaries and 50 persisted timeline entries per page.
  Explicit URL cursors page each source, and URL-backed event selection changes only the
  selected evidence instead of repeating persisted/live reads. A connected running-call
  page polls only the bounded live projection once per second and ignores stale timer
  messages; an ended-call page performs no live read.
- The workbench combines explicitly sourced persisted and live facts, exposes exact safe
  correlation/provenance fields, preserves inert remote payload rendering, compares the
  latest comparable permitted variable snapshots, and keeps archive gaps, live loss and
  unavailable timing distinct rather than implying continuity.
- Persisted list/detail reads and the live projection now load independently. When the
  repository is unavailable, an authorized direct call-detail request can still render
  its bounded live-only evidence while labeling persisted fields unavailable and keeping
  live revision/loss and an unknown tool outcome explicit. A focused endpoint test first
  failed because the unavailable persisted read prevented any live read; the corrected
  endpoint file passes 14 tests and the complete Console suite passes 50 tests.
- The existing definition-driven archive-recovery scenario now also reads the real room's
  live-inspection buffer while the writer is repeatedly failing. It verifies the completed
  host tool and accepted variable revision with their original participant/turn/tool
  correlation, after conversation already continued. Recovery still drains each retained
  fact once and closes the archive. This supplies the end-to-end outage half of the
  independently tested Console live-only presentation boundary.
- Calls already supplied bounded missing-sequence samples and duplicate ID/sequence counts,
  but the Console reduced that evidence to a generic missing count and hid duplicates. The
  archive notice now reports each bounded count explicitly. The focused endpoint file passes
  15 tests, the complete Console suite passes 51 tests, and root format,
  warnings-as-errors compilation and strict Credo checks pass.
- A failed tool event with an explicitly unknown outcome now renders its permitted payload
  as inert evidence. When neither persisted nor live evidence exists, the call detail shows
  a generic not-found result without leaking backend error atoms. Closing a connected detail
  LiveView prevents any further live read beyond a complete polling interval. The focused
  endpoint file passes 17 tests, the complete Console suite passes 53 tests, and root format,
  warnings-as-errors compilation and strict Credo checks pass.
- Calls live disclosure removes transcript content denied by source policy and credential
  sentinels before returning a timeline. The Console orders out-of-order evidence by source
  time and deduplicates repeated identities within one source. Reconnecting starts a fresh
  view, performs bounded list (25), persisted-detail (50) and live reads, and does not
  republish evidence retained only by the prior view after both sources report the call
  missing. The Calls suite passes 35 tests, the Console suite passes 55 tests, and root
  format, warnings-as-errors compilation and strict Credo checks pass.
- An ended-call fixture includes script-like content and an HTTPS resource URI. The Console
  escapes the script content and preserves the URI only as inert text, emitting no matching
  `href` or `src`; the focused endpoint file passes 18 tests. This closes the remote-content
  portion of the forbidden-content acceptance check without adding resource inspection.
- Rendered review at 1440px and 390px verified the list/detail workflow, event selection,
  call/history pagination, variable diff, mobile reading order and zero horizontal overflow.
  The approved screenshots are `.impeccable/review/desktop.png` and
  `.impeccable/review/mobile.png`; the final UI review disposition was `ship`.
- A rendered 390px repository-outage check retained a 390px document width, showed the
  live-only/tool-failure evidence, and produced no browser errors.
- A rendered 390px archive-gap check showed `Archive gap: 2 missing sequences · 1 duplicate
  ID · 1 duplicate sequence` with the unknown tool payload, retained equal 390px document
  and viewport widths, and produced no browser errors.
- A pre-delivery runtime-loss check now distinguishes persisted lifecycle state from a live
  room. The list labels `running` rows as `Running record`; when the live projection is absent,
  detail and refresh paths show `Runtime unavailable` and `End time unavailable`, then stop
  polling instead of claiming the call is live or still timing it. No terminal fact, end time,
  replay, reconciliation, retention, or deletion is invented. The focused endpoint contract
  first failed twice on the former `Live`/`Persisted` labels, then passed 20 tests; the complete
  Console suite passes 91 tests. Full umbrella verification passes 994 tests with 15 explicitly
  excluded integrations, plus formatting, warnings-as-errors compilation, unused-dependency
  checking, and strict Credo over 803 files.
- The LiveView inspection stylesheet now lives in `assets/css` rather than the Elixir `lib`
  tree. Its controller continues to embed, hash, and serve the same bounded asset, so this
  source-boundary correction changes neither the route nor its immutable caching contract.
- A fresh deterministic WebRTC call was left running while the development VM was stopped,
  then inspected after restart. Its current-schema persisted ledger rendered with the explicit
  runtime-unavailable state. Desktop and 390px confirmation captures had equal viewport/body/
  document widths, zero axe violations or incomplete checks, and no browser errors.

- Final root verification passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
  `mix deps.unlock --check-unused`. The full suite completed with 362 tests, no failures,
  and six tagged integration exclusions. Because the machine's default PostgreSQL required
  unavailable password authentication, the suite used an isolated temporary PostgreSQL
  instance without external credentials.

The runnable outcome, acceptance/failure checks, responsive browser review, documentation
updates and common gates are complete.

## Specification review

Local design review on 2026-09-08 checked history/admission prerequisites, a useful
live-and-ended call workflow, tenant isolation, independent client visibility, interval
privacy, read-only ownership, bounded subscribers and honest archive lag. It kept audio
monitoring in its existing milestone and operator authentication explicit before exposure.
The subsequent approved console/gateway boundary received a focused specification review:
the earlier observable-call slice supplies the Phoenix shell, inspection uses public
Calls/live-projection interfaces, and browser authorization remains separate from API-key
and caller-token admission. No new prerequisite or tenant administration UI is implied.
Implementation and browser evidence are recorded above.
