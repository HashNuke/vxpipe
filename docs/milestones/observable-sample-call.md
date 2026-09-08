# Observable sample call

Status: implementation in progress. The reusable gateway mounting and single-listener
configuration checkpoint completed on 2026-09-08. A separate Phoenix shell,
`vxpipe_console` / `Vxpipe.Console`, is approved; the reusable gateway remains independent
of Phoenix and UI dependencies.
Prerequisites: [Definition-driven call](definition-driven-call.md).
Sources: [Security and observability](../architecture.md#security-and-observability);
[Gateway/console boundary](../gateway-console-boundary.md);
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
- Introduce the separate Phoenix application `vxpipe_console`, using the
  `Vxpipe.Console` namespace, to own the endpoint, dashboard and sample frontend assets.
  Keep `vxpipe_gateway` as reusable Plug/protocol handling and connection supervision,
  with no Phoenix or UI dependency. Console depends on gateway public interfaces;
  neither owns Repo. Preserve existing application names, process owners, RTVI/WebRTC
  contracts, configured CORS and Caddy/Vite development behavior; do not regenerate
  the gateway as a Phoenix application. This is additive: include the existing gateway
  as a dependency and build the shell in the new console app, not a gateway rewrite.
- The console's Phoenix endpoint mounts/invokes the gateway Plug in-process. It owns
  the single application HTTP listener/port for console pages and call endpoints;
  disable the gateway's separate listener but retain its session/connection runtime.
  There is no internal HTTP reverse-proxy hop. A standalone gateway listener is an
  alternative for other hosts, not a second listener in the console deployment.
- Reuse and verify gateway Plug/protocol interfaces with explicit supervision and
  configuration, plus an optional standalone listener. Make only minimal mounting or
  configuration adjustments if integration requires them. A consuming Elixir application
  can use the gateway without the console. This is a planned verified integration
  contract, not a claim that the existing router is already a supported mounting interface.
- Move sample asset ownership to the console during implementation without rewriting
  React or replacing its client/UI dependencies with LiveView. Retain Vite for
  development/build tooling and serve built assets from the console in a release.
  Select the operational dashboard implementation, with LiveDashboard a candidate;
  full VM/ETS inspection is platform-operator access, never tenant call inspection.

## Implementation checklist

- [x] Red-test project-owned gateway mounting/startup and single-listener configuration
  before adding the console integration.
- [x] Add the approved console shell using the existing gateway dependency; verify
  explicit startup/mounting and adjust gateway configuration only where needed, without
  moving protocol ownership into Phoenix or rewriting the gateway.
- [x] Select/document the dashboard mechanism and trusted operator-access boundary;
  keep Phoenix/dashboard/frontend dependencies in the console application.
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
- [ ] A consuming host mounts the gateway with documented supervision/configuration
  while its standalone listener is disabled, without Phoenix/console dependencies.
  The optional standalone listener also preserves existing protocol/CORS behavior.
- [ ] Console pages and gateway call routes share the Phoenix HTTP listener without
  an internal HTTP hop; disabling the gateway listener does not stop its connection runtime.
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
6. Run the documented gateway embedding fixture without the console or Phoenix; check
   joining through its mounted routes, and separately through the standalone listener.
   In the console deployment, verify both pages and call routes use its one HTTP port
   and no gateway standalone listener is running.

## Scope boundaries

No persistent per-call timeline, database prerequisite, hosted metrics backend, alerting
service, distributed tracing rollout, tenant-wide admin console, raw payload logging,
silent audio monitoring, packet capture or new client protocol. The approved Phoenix
shell does not authorize replacing gateway internals, rewriting the React sample in
LiveView or introducing a production operator-login product.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and all acceptance/failure checks above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, index entry, architecture/user docs and implementation labnote
  with actual focused-test, integration and rendered-browser evidence.

Implementation evidence, checkpoint 1 (2026-09-08): added the public
`Vxpipe.Gateway.HTTP.Mount` Plug. It mounts gateway health/API routes at root or beneath an
explicit host prefix, preserves the gateway's CORS/parser/router behavior, halts claimed
responses, and leaves non-gateway host pages untouched. Focused tests demonstrate the mount
while the standalone HTTP supervisor is absent and the named session/WebRTC runtime remains
active. Gateway and umbrella gates pass with call engine `102 tests, 0 failures (1 excluded)`
and gateway `43 tests, 0 failures (3 excluded)`. Phoenix and dashboard dependencies are not
introduced by this checkpoint; the milestone remains incomplete.

Implementation evidence, checkpoint 2 (2026-09-08): added the minimal
`vxpipe_console` umbrella application on Phoenix 1.8.13 with `Vxpipe.Console` modules and a
direct dependency on the reusable gateway. The Console application prepares the gateway mount
once at runtime and passes it into `Vxpipe.Console.Endpoint`; the endpoint invokes that Plug
before its own router. Development disables only the gateway listener and enables the Console
endpoint. `ConnTest` proves the Console root page and gateway health/API namespace share the
endpoint, while live `bin/dev` evidence shows one BEAM listener on `127.0.0.1:4000` and identifies
it as `Vxpipe.Console.Endpoint`. The session and WebRTC supervisors remain active. The initial
shell rendered without browser errors at desktop and 390x844 mobile; sample asset ownership and
the diagnostics UI remain pending. Final gates pass with call engine `102 tests, 0 failures
(1 excluded)`, gateway `43 tests, 0 failures (3 excluded)`, and Console `2 tests, 0 failures`.

Implementation evidence, checkpoint 3 (2026-09-08): selected Phoenix LiveDashboard 0.9.1
for VM/runtime inspection and reserved the separate `/diagnostics` page for Vxpipe call-path
measurements. Both routes use a project-owned fail-closed operator plug. Diagnostics are off by
default; repository development enables only direct IPv4/IPv6 loopback access and Caddy does not
route the namespace. This is explicitly not production proxy authentication. Focused tests prove
disabled and non-loopback requests return 404 while an enabled loopback operator can load both
surfaces. Chromium rendered LiveDashboard at desktop and 390x844 mobile without browser errors;
the HTTPS Caddy path continued to serve the voice playground, not diagnostics. Call telemetry and
the finished Vxpipe dashboard remain pending. Final gates pass with call engine `102 tests,
0 failures (1 excluded)`, gateway `43 tests, 0 failures (3 excluded)`, and Console `4 tests,
0 failures`.

## Specification review

Local design review on 2026-09-08 checked the early prerequisite, observable browser
outcome, framework-independent emitters, synchronous-handler constraints, bounded metric
cardinality, operator-only access and preservation of existing protocols. The subsequent
approved gateway/console split was reviewed for dependency direction, mountable and
standalone gateway acceptance, React asset ownership and the unchanged prerequisite.
It supersedes the earlier pending Phoenix choice and in-place gateway conversion proposal;
persistence/inspection remain in their later slices and operator authentication remains
explicit. This records design review only, not implementation or UI verification.
