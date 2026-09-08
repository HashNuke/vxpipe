# Observable sample call

Status: not implemented. Scope requested by the user; specification reviewed locally
on 2026-09-08. Phoenix adoption remains a separate pending choice, not an approved migration.
Prerequisites: [Definition-driven call](definition-driven-call.md).
Sources: [Security and observability](../architecture.md#security-and-observability);
[Telemetry handler execution](https://hexdocs.pm/telemetry/telemetry.html#attach/4);
[LiveDashboard candidate](https://hexdocs.pm/phoenix_live_dashboard/Phoenix.LiveDashboard.html).

## Runnable outcome

A developer runs a sample conversation and watches a separate operational dashboard
show request latency, available model/speech timing, provider errors and VM health.
They trigger a controlled provider failure and can distinguish that failure from a
slow response or missing measurement. The existing voice console still works unchanged.

## Specification

- Deliver a real browser dashboard using the existing sample call path, not only event
  emitters or console output. Keep it separate from the responsive React voice console;
  navigation between the sample and diagnostics must not require adding a debug bar there.
- Instrument the gateway and engine boundaries that own the measurements. Emit standard
  `:telemetry` events independently of the UI framework. An embedded engine host can
  attach its own reporter without starting the gateway, browser, database or Phoenix.
- Cover the implemented subset: HTTP request duration/outcome, active room count,
  model time to first token, TTS time to first audio where observable, safe provider
  failure categories, and sampled VM memory/run-queue health. Document event names,
  units, start/end boundaries, aggregation and provenance. Later slices add their own
  tool/transfer/storage/transport measurements rather than this slice simulating them.
- Measure elapsed time using a compatible monotonic clock. Missing or interrupted
  observations are not zero latency or successful completion. Distinguish provider
  first audio, gateway egress acceptance and actual browser playout; do not infer that
  a remote listener heard audio or subtract unrelated client/server clocks.
- Use bounded metric dimensions such as operation, configured provider and outcome.
  Call/participant/turn/request correlations belong in restricted event context or
  later call inspection, not unbounded metric labels. Do not include transcripts,
  prompts, variable values, tool payloads, credentials, authorization headers, tokens
  or private capability handles in general metric events or labels.
- `:telemetry` handlers run in the emitting process. Project-owned handlers must do
  bounded local work, with no SQL/network requests, browser sends or synchronous
  calls into the room. Any downstream queue/history is bounded; collector failure or
  a slow dashboard cannot backpressure media. Sample VM/queue observations outside
  hot callbacks, not an expensive sample or event per audio packet. An embedding
  host remains responsible for the handlers it installs.
- Observation is best effort, not the archival event bus or a durable history store.
  Show when collection is unavailable or data is stale rather than displaying stale
  health as current. Detach/clean up project handlers on collector shutdown so restart
  does not double-count observations. Test our integration, not Telemetry internals.
- Enable diagnostics explicitly through namespaced application options. The early
  slice uses a restricted, trusted development setup with synthetic data, not public
  admission. A tailnet URL or a caller's join token is not operator authorization.
  Default exposure is off unless configured; outside that trusted setup require a
  documented operator-auth boundary before enabling routes or subscriptions.
- Phoenix plus LiveDashboard is a candidate implementation, not a requirement implied
  by accepting this milestone. Resolve that choice before implementation. If selected,
  migrate the existing gateway in place, preserving application names, process owners,
  RTVI/WebRTC contracts, configured CORS, and Caddy/Vite development behavior. Retain
  React for the playground. Do not add Repo ownership to the gateway. A full VM/ETS
  dashboard is platform-operator access, never a tenant-facing call inspection page.

## Implementation checklist

- [ ] Select/document the dashboard mechanism and trusted operator-access boundary;
  record any separately approved Phoenix migration and its dependency ownership.
- [ ] Write red tests for project-owned timing/outcome projection, missing observations,
  safe metadata, bounded dimensions and reporter restart behavior.
- [ ] Instrument existing request/model/speech boundaries and add sampled VM measurements.
- [ ] Connect a bounded reporter to a separate dashboard and the existing sample entry.
- [ ] Provide a deterministic local provider fixture for controlled delay/failure, without
  relying on hosted credentials or adding failure switches to production call input.
- [ ] Document how an embedded host consumes the same events without the dashboard.
- [ ] Inspect desktop/mobile dashboard states and the unchanged voice console in a browser.

## Acceptance and failure checks

- [ ] A sample text/audio exchange produces correctly attributed measurements; a scripted
  provider failure appears as a safe error category, not successful/zero-duration work.
- [ ] No first token/audio, cancellation and unavailable provider measurements remain
  explicitly missing/incomplete. Known fixture timings match documented boundaries.
- [ ] Synthetic secret/text/variable sentinels never enter metric payloads, labels or
  unprivileged responses. Many unique call IDs do not create one metric series per call.
- [ ] Stop/restart the collector and disconnect/saturate the dashboard: calls continue,
  retained buffers remain bounded, missing data is visible and measurements are not doubled.
- [ ] An embedded host receives engine events without gateway/database/UI dependencies.
- [ ] Disabled or unauthorized diagnostic requests/subscriptions fail closed; ordinary
  callers cannot access operator routes. VM-wide inspection is not granted by tenant scope.
- [ ] Existing room creation, RTVI joining, text/audio, CORS and interruption checks remain
  green. Opening diagnostics neither creates a participant nor captures extra audio/text.

## Manual verification

1. Enable the documented trusted development diagnostics and run the existing sample.
2. Open the separate dashboard and exchange typed/spoken input; verify request/VM metrics
   and available model/TTS timings, with units and measurement boundaries visible.
3. Use the controlled local fixture to delay, fail and omit a first-output observation;
   confirm the dashboard distinguishes slow, failed and unavailable results.
4. Stop/restart collection or disconnect the dashboard while conversing. Verify ongoing
   audio, bounded diagnostic state and honest stale/missing status after reconnection.
5. Disable diagnostics, try an ordinary caller session, and test the embedded reporter.
   Inspect desktop/mobile views without changing the voice console layout.

## Scope boundaries

No persistent per-call timeline, database prerequisite, hosted metrics backend, alerting
service, distributed tracing rollout, tenant-wide admin console, raw payload logging,
silent audio monitoring, packet capture or new client protocol. General Phoenix adoption
and production operator-login implementation are not silently approved here.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and all acceptance/failure checks above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, index entry, architecture/user docs and implementation labnote
  with actual focused-test, integration and rendered-browser evidence.

Implementation evidence: none yet. Specification review does not complete the milestone.

## Specification review

Local design review on 2026-09-08 checked the early prerequisite, observable browser
outcome, framework-independent emitters, synchronous-handler constraints, bounded metric
cardinality, operator-only access and preservation of existing protocols. It separated
the pending Phoenix choice from the requested outcome and left persistence/inspection
to their later slice. This records design review only, not implementation or UI verification.
