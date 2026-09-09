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
  slice uses a trusted development setup with synthetic data, not public admission.
  Default exposure is off unless configured. This slice adds no page authentication:
  deployments decide whether to expose the enabled Console. API keys authenticate
  call-management endpoints and join tokens authorize call admission; neither becomes
  a Console or LiveDashboard login.
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
- [x] Move the unchanged React/Vite playground source under Console ownership, supervise
  its development watcher through the Phoenix endpoint, and package its built assets in
  a Console release.
- [x] Select/document the dashboard mechanism and trusted operator-access boundary;
  keep Phoenix/dashboard/frontend dependencies in the console application.
- [x] Write red tests for project-owned timing/outcome projection, missing observations,
  safe metadata, bounded dimensions and reporter restart behavior.
- [x] Instrument existing request/model/speech boundaries and add sampled VM measurements.
- [x] Connect a bounded reporter to a separate dashboard and the existing sample entry.
- [x] Provide a deterministic local provider fixture for controlled delay/failure, without
  relying on hosted credentials or adding failure switches to production call input.
- [x] Document how an embedded host consumes the same events without the dashboard.
- [x] Inspect desktop/mobile dashboard states and the unchanged voice console in a browser.

## Acceptance and failure checks

- [ ] A sample text/audio exchange produces correctly attributed measurements; a scripted
  provider failure appears as a safe error category, not successful/zero-duration work.
- [ ] No first token/audio, cancellation and unavailable provider measurements remain
  explicitly missing/incomplete. Known fixture timings match documented boundaries.
- [ ] Synthetic secret/text/variable sentinels never enter metric payloads, labels or
  unprivileged responses. Many unique call IDs do not create one metric series per call.
- [ ] Stop/restart the collector and disconnect/saturate the dashboard: calls continue,
  retained buffers remain bounded, missing data is visible and measurements are not doubled.
- [x] An embedded host receives engine events without gateway/database/UI dependencies.
- [ ] A consuming host mounts the gateway with documented supervision/configuration
  while its standalone listener is disabled, without Phoenix/console dependencies.
  The optional standalone listener also preserves existing protocol/CORS behavior.
- [ ] Console pages and gateway call routes share the Phoenix HTTP listener without
  an internal HTTP hop; disabling the gateway listener does not stop its connection runtime.
- [x] Disabled diagnostic requests/subscriptions fail closed. When enabled, diagnostics
  require no additional authentication; API keys retain only their call-management role
  and join tokens retain only their call-admission role.
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
measurements. Diagnostics are off by default. The initial implementation used a development-only
loopback exposure check; the subsequent access correction below supersedes that behavior.
Chromium rendered LiveDashboard at desktop and 390x844 mobile without browser errors. Call
telemetry and the finished Vxpipe dashboard remain pending. Final gates passed with call engine
`102 tests, 0 failures (1 excluded)`, gateway `43 tests, 0 failures (3 excluded)`, and Console
`4 tests, 0 failures`.

Implementation evidence, access correction (2026-09-08): enabled Console diagnostics add no
authentication layer. The project-owned Plug now owns only the enabled/disabled setting, and an
enabled request behaves the same for loopback and non-loopback peers. Caddy routes
`/diagnostics` and `/diagnostics/*` to the Console endpoint, including the LiveView socket path;
API-key authentication remains confined to call-management endpoints and join-token
validation to call admission. Neither protects Console or LiveDashboard routes. This
correction supersedes the checkpoint-3 loopback restriction.

Implementation evidence, checkpoint 7 (2026-09-09): added the Console-owned bounded
Telemetry reporter. Its hot-path callback performs atomic admission plus a local send;
the configured pending limit produces an explicit dropped-event count rather than an
unbounded mailbox. State contains only closed-dimension counts, duration aggregates and
the latest runtime gauges with age information. Focused tests cover six event projections,
payload-sentinel exclusion, saturation, abrupt replacement without double attachment and
normal detach. Umbrella gates pass with call engine `107 tests, 0 failures (1 excluded)`, gateway
`45 tests, 0 failures (3 excluded)`, and Console `7 tests, 0 failures`. The custom measurement
page remains pending.

Implementation evidence, checkpoint 8 (2026-09-09): replaced the diagnostics placeholder
with a responsive LiveView instrument board backed by the reporter's latest snapshot. It
shows collection freshness/drops, current runtime gauges, HTTP timing, model first-output
timing and terminal outcomes, TTS first-audio timing, safe provider failures, and explicit
empty/unavailable states. The page uses a 250 ms reporter-read timeout and keeps no browser
history. Its content-hashed Phoenix/LiveView client asset is packaged by Console rather than
loaded from a hosted service. The header links to both LiveDashboard and the existing voice
sample without altering that sample.

The Impeccable finish review returned `ship` with no material fixes. It confirmed the
status-rail-to-workbench hierarchy, restrained operational color use, explicit failure
states and responsive single-column adaptation as a direct extension of the established
Operator's Bench system. No reusable design-system addition was warranted. Umbrella gates
pass with call engine `107 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures
(3 excluded)`, and Console `10 tests, 0 failures`.

Implementation evidence, checkpoint 9 (2026-09-09): added an opt-in supervised local
model fixture with fixed success, 1.5-second delay, provider-failure and invalid-empty-output
scenarios. A one-shot selection is consumed atomically and resets to the configured default.
The trusted runtime setting injects it at the Jido request-transformer boundary; call
definitions, invocation bodies and RTVI messages gain no fixture switch. The normal room,
gateway, optional TTS and payload-free Telemetry paths remain in use, with the closed
`:local_fixture` provider dimension. The diagnostics board shows controls only while the
fixture is configured.

Focused tests cover supervision selection, fixed scenario validation/consumption, request
projection, known delay, complete success/failure/no-output room turns, bounded provider
attribution and LiveView arming. Chromium verified the controls at 1440x900 and 390x844 with
no horizontal overflow or browser errors. A live delayed typed turn displayed and spoke
`Local fixture response.`, reported about 1.5 seconds to first output under Local fixture,
and independently reported Deepgram first audio. A live failure produced no assistant text
and appeared as Local fixture unavailable with missing first output.

The Impeccable finish review returned `ship` with no material fixes. It confirmed that the
fixed opt-in controls extend the existing Operator's Bench hierarchy at both viewports and
that the neutral selected state does not imply a healthy or failed measurement. The design
documentation review found no reusable system primitive to add. Runtime configuration checks
also confirmed that fixture mode skips the hosted-model credential while normal development
mode retains it. Umbrella gates pass with call engine `115 tests, 0 failures (1 excluded)`,
gateway `45 tests, 0 failures (3 excluded)`, and Console `12 tests, 0 failures`.

Implementation evidence, checkpoint 10 (2026-09-09): the engine now exposes its complete
current event list through `Vxpipe.CallEngine.Telemetry.events/0`. An engine-local test attaches
an ordinary Telemetry handler to that contract and receives a runtime observation without
depending on the gateway, Console, Phoenix, or a database. The engine README documents stable
handler identity, detach-before-attach startup, orderly cleanup, native-duration conversion,
bounded local callback work and the host collector's responsibility to bound admission. The
focused red test first failed because the event-list function was absent, then passed after the
public contract was added. The first root run exposed a global-Telemetry test-isolation race
between async STT and TTS tests; their assertions now match the owning capability rather than
claim unrelated concurrent events. Umbrella gates then passed with call engine `116 tests,
0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`, and Console `12 tests,
0 failures`.

Implementation evidence, checkpoint 11 (2026-09-09): moved the unchanged React/Vite source
from the former top-level sample directory into `vxpipe_console/assets`. That checkpoint
initially retained a separate Goreman `assets` process on the same development ports. The root
`assets.build` alias targets only the Console child and writes
the ignored production bundle to `vxpipe_console/priv/static`; the Console serves the no-store
SPA index and only hashed `/assets/*` files with immutable caching. Missing release assets now
return an explicit 503 instead of a placeholder page.

The first endpoint run failed with the old placeholder response and hidden missing-bundle state;
the focused green run passed `5 tests, 0 failures`. The relocated frontend passed `3 tests,
0 failures`, its production build completed, and the Goreman shell contract passed. Chromium
rendered the unchanged create-room page through the Vite HTTPS origin and the built Console
endpoint at 1440x900 and 390x844 with no page errors or horizontal overflow. A child-app
production release assembled successfully and contained the index plus six generated assets.
An initial root release attempt correctly failed because the umbrella has no explicit release
definition; documentation now gives the verified Console child release command rather than
adding broader release policy in this milestone. The complete umbrella gates pass with call
engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`, and
Console `13 tests, 0 failures`.

Implementation evidence, checkpoint 12 (2026-09-09): completed Console development ownership
by moving the Vite command into the Phoenix endpoint's watcher configuration. `bin/dev` and its
Procfile no longer expose an `assets` process; Goreman manages the BEAM application, Watchman
reload helper and optional Caddy ingress, while Vite remains a Node child supervised with the
Console endpoint. This supersedes only checkpoint 11's process-management detail: the same Vite
source, ports, proxy behavior, Caddy routes and release bundle contract remain in force.
The focused shell test passes, and a live default-HTTPS run shows only `vxpipe`, `reloader`
and `caddy` Goreman labels while Vite reports its loopback 5174 listener under `vxpipe`.
The frontend's three tests and production build pass. Chromium rendered the HTTPS entry at
1440x900 and 390x844 without page errors or horizontal overflow. The complete umbrella gates
pass with call engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures
(3 excluded)`, and Console `13 tests, 0 failures`.

Implementation evidence, checkpoint 13 (2026-09-09): the diagnostic LiveView transport now
uses a Console-owned socket whose connect callback shares the HTTP pipeline's enablement
decision. The focused test first failed because that socket did not exist and the endpoint
still mounted the unconditional dependency socket. It now verifies a refused disabled
connection, an unauthenticated enabled connection and the endpoint wiring, while the existing
HTTP tests retain disabled 404 and enabled local/remote behavior. The focused Console endpoint
run passes `6 tests, 0 failures`. A live HTTPS diagnostics page connected through the new socket,
reported `Collecting`, and produced no browser errors. The complete umbrella gates pass with
call engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`,
and Console `14 tests, 0 failures`.

Implementation evidence, checkpoint 14 (2026-09-09): a live Watchman-equivalent restart
exposed that both the initial `npm` watcher and a direct Vite CLI watcher survived their
Phoenix parent and retained port 5174. The Console asset entrypoint now creates Vite through
its programmatic API, consumes the parent port's stdin, closes the server once on EOF or
termination and then exits. The Node lifecycle test first failed because that module was
absent and now proves idempotent close/exit behavior. The shell contract also failed first
for the newly explicit missing-Node requirement and now passes. In a fresh default-HTTPS
run, restarting only `vxpipe` removed old Vite PID `1966646`; replacement PID `1966898`
became the sole listener on 5174 without a port-conflict retry.
The combined asset suite passes one Node lifecycle test and three Vitest interface tests;
the production bundle and shell development contract also pass. Chromium reopened the HTTPS
voice entry after the restart with no browser errors or horizontal overflow. The complete
umbrella gates pass with call engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests,
0 failures (3 excluded)`, and Console `14 tests, 0 failures`.

## Specification review

Local design review on 2026-09-08 checked the early prerequisite, observable browser
outcome, framework-independent emitters, synchronous-handler constraints, bounded metric
cardinality, explicit diagnostics enablement and preservation of existing protocols. The
subsequent approved gateway/console split was reviewed for dependency direction, mountable and
standalone gateway acceptance, React asset ownership and the unchanged prerequisite.
It supersedes the earlier pending Phoenix choice and in-place gateway conversion proposal;
persistence/inspection remain in their later slices. The access correction records the later
decision not to add Console/LiveDashboard authentication in this slice. This records design
review only, not implementation or UI verification.
