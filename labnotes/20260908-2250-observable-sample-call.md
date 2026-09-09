# Observable sample call

Milestone: [Observable sample call](../docs/milestones/observable-sample-call.md), sequence 2.
Started: 2026-09-08.

## Checkpoint 1: reusable gateway mounting boundary

The repository begins this milestone with an optionally supervised standalone Bandit listener
inside `vxpipe_gateway`. Its HTTP endpoint is already a Plug, but it always owns every path it
receives and its mounting behavior is not a public, tested host-composition contract. The test
environment disables the standalone listener while retaining the named session and WebRTC
connection supervisors.

The first slice will red-test a composable gateway mount that:

- claims `/healthz` and the `/api` namespace while leaving host/console pages untouched;
- supports a host path prefix without changing the gateway router's own paths;
- halts after a claimed response so a downstream host router cannot send twice;
- preserves configured CORS behavior; and
- works while the standalone listener is disabled and the gateway runtime remains active.

This boundary is intentionally implemented before adding Phoenix. It gives the future console
one in-process HTTP listener while leaving standalone gateway embedding available and keeping
Phoenix dependencies out of `vxpipe_gateway`.

### Red, green, and verification evidence

- Red command: `mix test test/vxpipe/gateway/http/mount_test.exs` from the gateway child.
- Red result: compilation failed because `Vxpipe.Gateway.HTTP.Mount.init/1` did not exist.
- Green result: `4 tests, 0 failures`.
- Root mounting claims `/healthz` but not `/diagnostics`; prefixed mounting rewrites
  `/voice/healthz` to the existing gateway route and records `voice` in `script_name`.
- A mounted preflight request retained its configured origin and method response headers.
- An unknown path under the mounted `/api` namespace returned the gateway's 404 and halted.
- The same test process observed no `Vxpipe.Gateway.HTTP.Supervisor`, while the named session
  and WebRTC connection supervisors were running. The host can therefore own the listener
  without disabling gateway protocol runtime.
- The complete gateway suite passed `43 tests, 0 failures (3 excluded)`.
- Umbrella gates passed `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine
  `102 tests, 0 failures (1 excluded)`, and gateway `43 tests, 0 failures (3 excluded)`.

## Checkpoint 2: Phoenix Console shell and shared listener

Current Phoenix documentation and Hex metadata identified Phoenix 1.8.13 as the current release.
The new `vxpipe_console` application uses that compatible release with Bandit and a direct
umbrella dependency on `vxpipe_gateway`. It deliberately has no Ecto, separate domain layer,
LiveView, dashboard, or frontend build stack yet.

The Console application prepares `Vxpipe.Gateway.HTTP.Mount` once from the gateway's runtime
HTTP route settings and passes it as endpoint startup configuration. This replaced an initial
working `Endpoint.init/2` implementation after Phoenix 1.8 warned that callback is deprecated.
`Vxpipe.Console.GatewayMount` reads the prepared endpoint configuration and delegates claimed
requests before the Console router. Development configuration disables the gateway's standalone
listener and enables the Console endpoint on the existing port.

### Red, green, and verification evidence

- Red command: `mix test test/vxpipe/console/endpoint_test.exs` from the Console child.
- Red result: `2 tests, 2 failures`; `Vxpipe.Console.Endpoint.init/1` did not exist.
- Green result after the lifecycle refactor: `2 tests, 0 failures` with no warnings.
- The tests serve the Console root and gateway `/healthz` through the same endpoint, retain the
  gateway session/WebRTC supervisors, observe no standalone gateway HTTP supervisor, and prove
  an unknown `/api` route remains a halted gateway 404 rather than falling into Console routing.
- A fresh `bin/dev` run logged only `Vxpipe.Console.Endpoint` at `127.0.0.1:4000`. Socket
  inspection found one BEAM listener on that port. Direct requests to `/` and `/healthz` both
  returned 200 from it.
- Chromium rendered the initial routing shell at 1440x900 and 390x844 with empty browser error
  output. The first launch required the documented `--no-sandbox` flag on this host because
  unprivileged Chromium namespaces are unavailable. This shell is not the milestone's final
  presentation; the existing React sample and separate diagnostics surface remain pending.
- Runtime URL configuration reports the Caddy HTTPS origin when that development mode is active,
  while the sole application listener stays on loopback. The temporary shell uses an empty data
  favicon so browser inspection does not generate an irrelevant Console route miss.
- Final checkpoint gates passed `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine
  `102 tests, 0 failures (1 excluded)`, gateway `43 tests, 0 failures (3 excluded)`, and Console
  `2 tests, 0 failures`.

## Checkpoint 3: protected diagnostics mechanism

Phoenix LiveDashboard 0.9.1 is the selected platform VM/runtime view. A separate Vxpipe
`/diagnostics` page will present bounded call-path observations as they are implemented. LiveView,
LiveDashboard, Phoenix HTML, and PubSub remain direct or transitive Console dependencies; neither
the gateway nor engine gains a Phoenix dependency.

The first access boundary is deliberately narrow. Diagnostics are disabled in shared configuration.
Repository development enables them only when the direct connection address is IPv4 or IPv6
loopback. The Caddy configuration does not forward `/diagnostics` or its LiveView socket, so the
tailnet HTTPS origin continues to serve the voice playground for that path. This is suitable for
local development only: loopback checks behind a reverse proxy would identify the proxy rather
than the operator. External exposure stays prohibited until an operator-auth mechanism protects
both routes and subscriptions.

### Red, green, and verification evidence

- The first focused run compiled the new dependencies but exceeded the command output window; no
  test process remained. The repeated red run reached ExUnit and failed because diagnostics
  configuration/routes did not exist. It also exposed an imprecise `%Plug.Conn{}` update in the
  test, corrected before implementation.
- Green focused result: `4 tests, 0 failures`.
- With default configuration, `/diagnostics` returns a plain 404. With explicit loopback
  development settings, the Vxpipe landing page and canonical LiveDashboard home load. A
  documentation-range non-loopback client still receives the same 404.
- Chromium rendered the LiveDashboard home at 1440x900 and 390x844. It showed current OTP,
  Elixir, Phoenix, dashboard, run-queue, process, port and memory data with empty browser error
  output. The initial Vxpipe page is only a routing placeholder and will be replaced by the
  call-measurement surface in this milestone.
- A request to the Caddy HTTPS `/diagnostics` path returned the existing voice-playground title,
  confirming that development routing does not expose the operator surface to the tailnet.
- Adding dependencies while the file watcher was live caused Goreman to stop when it observed
  the manifest before `mix deps.get` finished. A fresh `bin/dev` after dependency resolution
  started normally; no application defect or workaround remains in the runtime.
- Final checkpoint gates passed `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`, call engine
  `102 tests, 0 failures (1 excluded)`, gateway `43 tests, 0 failures (3 excluded)`, and Console
  `4 tests, 0 failures`.

## Access correction: enabled diagnostics without additional authentication

The later approved web-access decision supersedes checkpoint 3's loopback-only restriction.
API-key authentication belongs to API endpoints, and join tokens belong to call admission;
neither becomes an extra login for Console pages or LiveDashboard. Diagnostics remain disabled
by default through namespaced application configuration. When enabled, the same routes accept
loopback and non-loopback peers, and the deployment controls exposure of the Console endpoint.

The red focused Console test changed the expected non-loopback result from 404 to the diagnostics
page. It failed because the old access Plug still required the removed `:access` setting. The
implementation replaces that Plug with an enabled-setting-only gate and routes `/diagnostics`
plus `/diagnostics/*` through Caddy to the Console endpoint. This also covers the configured
LiveView socket under `/diagnostics/live`.

The corrected focused test passed `4 tests, 0 failures`. Caddy validation accepted the
updated route configuration. The umbrella format, warnings-as-errors compile, default tests,
and unused-lock checks all passed: call engine `102 tests, 0 failures (1 excluded)`, gateway
`43 tests, 0 failures (3 excluded)`, and Console `4 tests, 0 failures`. After a clean dev-stack
restart, agent-browser loaded the HTTPS diagnostics landing page and followed it to LiveDashboard
at desktop and 390x844 mobile viewports with no page or console errors. Runtime logs confirmed
that the tailnet request upgraded `/diagnostics/live` to a Phoenix LiveView WebSocket.

## Checkpoint 4: gateway request telemetry

The first framework-independent metric boundary is the reusable gateway Plug rather than the
Phoenix endpoint. `Vxpipe.Gateway.Telemetry` emits
`[:vxpipe, :gateway, :http, :request, :stop]` after every returned gateway response and before
reraising an exception. Its sole measurement is elapsed monotonic time in Erlang `:native` units.
Metadata is limited to a closed operation atom, a closed outcome atom, and the response status
when one exists. Raw paths, query strings, headers, bodies, and correlation IDs are excluded.

The red focused run selected the two new endpoint tests and failed both because no Vxpipe event
was emitted. The initial implementation then stopped at compilation because a literal atom list
is not accepted as an Elixir return typespec; using `nonempty_list(atom())` fixed that declaration.
The repeated focused run passed `2 tests, 0 failures (10 excluded)`. It covered a successful
health request, a path/query sentinel collapsed to `:unknown`, and invalid JSON reported as the
safe `:exception` outcome before the original parser exception was reraised. The gateway now
declares its direct `:telemetry` dependency rather than relying on a transitive package.
Umbrella format, warnings-as-errors compile, default tests, and unused-lock checks passed with
call engine `102 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`,
and Console `4 tests, 0 failures`.

## Checkpoint 5: model and TTS boundary telemetry

The engine now records model time to first non-empty output, terminal model request outcome,
TTS time to first decoded provider audio, and safe provider failures. The model terminal event
also records `first_output` as `:observed` or `:missing`; a failed or cancelled request never
manufactures a zero first-token observation. The TTS event occurs before output-sink acceptance,
so it makes no claim about gateway egress or remote browser playout.

Provider identifiers collapse to `:req_llm`, `:deepgram`, or `:other`. Outcomes and failure
reasons likewise collapse to finite documented atoms. The events contain no prompts, input or
output text, audio bytes, raw provider errors, model names, participant/call/request IDs, or
capability handles. The definition-driven startup path now carries the compiled `:req_llm`
provider category into the supervised agent coordinator; other embedding paths safely normalize
an omitted or unknown provider to `:other`.

The first red run selected one test accidentally because line selection used pre-format line
numbers. The corrected four-test selection failed all four intended observations: model first
output, model failure/missing output, TTS first audio, and TTS provider failure. After adding
the engine-owned event module and lifecycle fields, the four tests passed. Tightened full-map
assertions then passed both owning test files with `15 tests, 0 failures`. The call engine now
declares `:telemetry` directly instead of depending on Jido or another transitive package.
Umbrella format, warnings-as-errors compile, default tests, and unused-lock checks passed with
call engine `105 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`,
and Console `4 tests, 0 failures`.

## Checkpoint 6: sampled runtime health and STT failures

`Vxpipe.CallEngine.TelemetrySampler` is one explicitly named application child. Every configured
interval it samples the active child count from `RoomSupervisor`, total local BEAM memory bytes,
and the VM run queue, then emits `[:vxpipe, :call_engine, :runtime, :sample]` with empty metadata.
The sampler runs outside every room/media callback. Its public bounded `sample/1` call provides a
deterministic acknowledgement for tests and embedded operational checks.

The sampler red test failed because neither its module nor application child existed. The green
test uses a dedicated DynamicSupervisor and moves its active count from zero to one without a
sleep, then verifies that the application supervisor owns exactly one named sampler. The test
environment retains the real supervised child but sets its automatic interval to one hour so it
cannot race focused event assertions. The focused sampler run passed `2 tests, 0 failures`.

Review of the remaining speech boundary found that STT transport/provider failures had not yet
joined the common provider event. A focused red assertion failed on transport closure, then
passed after instrumenting provider/transport failures. Local unsupported-audio and media-overload
reasons are deliberately excluded because they are not provider failures. The combined sampler
and STT test run passed `5 tests, 0 failures`.

Umbrella format, warnings-as-errors compile, default tests, and unused-lock checks passed with
call engine `107 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`,
and Console `4 tests, 0 failures`.

## Checkpoint 7: bounded Console reporter

The Console now owns one optional `Vxpipe.Console.TelemetryReporter` process. Telemetry callbacks
perform only atomic admission and a local send. `max_pending_events` is a hard bound: once the
pending count reaches it, later observations increment a dropped counter instead of entering the
mailbox. Reporter state retains finite duration aggregates and counts plus only the latest runtime
sample. Raw event maps, request data, conversation data and provider payloads are not retained.

Duration aggregates use microseconds and keep count, total, minimum, maximum and latest values.
All dimension values are projected through fixed operation, provider, outcome, first-output,
capability and failure-category sets. Snapshots include the age of the last admitted event and
runtime sample so the dashboard can distinguish current, stale and missing information.

The first focused test run failed because the reporter module did not exist. The first green
attempt exposed that ordinary supervisor shutdown did not invoke the cleanup callback unless the
collector trapped exits. The process now traps exits for best-effort detach, while correctness
after an abrupt kill comes from replacement initialization detaching the stable handler identifier
before attaching it again. The focused suite passed `3 tests, 0 failures`, and the complete Console
suite passed `7 tests, 0 failures`. Umbrella format, warnings-as-errors compile, default tests and
unused-lock checks passed with call engine `107 tests, 0 failures (1 excluded)`, gateway `45 tests,
0 failures (3 excluded)`, and Console `7 tests, 0 failures`. The browser measurement page remains
pending for this milestone.

## Checkpoint 8: live diagnostics board

The static diagnostics placeholder has been replaced by `Vxpipe.Console.DiagnosticsLive`.
It reads the reporter with a 250 ms timeout and refreshes its latest snapshot every second,
without keeping browser-side or server-side event history. The page renders explicit states
for a missing reporter, no observations, stale samples, dropped observations and the available
aggregate series. The Console packages the Phoenix and LiveView browser clients into a
content-hashed immutable asset, avoiding a hosted-script dependency.

The initial focused test run failed `3 tests, 3 failures` with `{:error, :nosession}` because
the diagnostics path was still a controller response. The LiveView test helper then identified
its documented test-only `lazy_html` dependency; adding that direct dependency allowed the
green focused run to pass `3 tests, 0 failures`. The complete Console suite passed `10 tests,
0 failures`. Tests cover a populated snapshot, a subsequent latest-snapshot refresh and the
honest collector-unavailable state.

The established Operator's Bench system guided a compact, asymmetric work surface rather than
a generic equal-card grid. The first rendered pass at 1440x900 and 390x844 had no horizontal
overflow and a connected LiveView socket. Its accessibility scan found one contrast problem on
healthy green text. Darkening that semantic color cleared the second scan with zero violations;
the confirmation pass also retained no current page or console errors. Navigation reached the
Phoenix system dashboard and the unchanged RTVI playground through the public HTTPS origin.
The Impeccable finish review returned `ship` with no material fixes. It approved the
status-rail-to-workbench hierarchy, restrained green/coral operational states, responsive
adaptation and truthful unavailable/empty states as a direct Operator's Bench extension.
The documentation review found no reusable design-system addition to promote. Umbrella gates
then passed: format check, warnings-as-errors compilation, default tests and the unused-lock
check. Results were call engine `107 tests, 0 failures (1 excluded)`, gateway `45 tests, 0
failures (3 excluded)`, and Console `10 tests, 0 failures`.

API-key authentication remains the call-management endpoint contract, and join tokens remain
the call-admission contract. Console and LiveDashboard routes intentionally receive no additional
application authentication.

## Checkpoint 9: deterministic local model fixture

The next dashboard slice needed reproducible delay, failure and missing-output behavior without
putting diagnostic switches into production call input. The first focused engine run failed
`4 tests, 3 failures` because the fixture process did not exist. A separate startup projection
test then failed because the resolved activation still identified only ReqLLM, and provider
dimension tests demonstrated that an otherwise working live failure appeared as `Other`.

`Vxpipe.CallEngine.Diagnostics.ModelFixture` now owns a fixed, application-configured scenario
set. It atomically hands one scenario to the Jido request transformer and resets to its configured
default. Success and delayed success return fixed local text, failure produces the normal safe
provider-unavailable path, and no-output exercises invalid-response handling without fabricating
content or first-output timing. The deliberate delay runs in the model worker. Base configuration
disables the process;
`VXPIPE_DEV_MODEL_FIXTURE` enables it in repository development, removes the Gemini credential
requirement, and exposes only the supervised process to the Console controls. No call definition,
invocation, room-creation body or RTVI message accepts a fixture selector.

Focused green runs covered fixed scenario validation/consumption, startup projection, request
projection and the complete room path for success, failure and no output. The 20 ms transformer
test verified that configured delay is applied before output. Telemetry and reporter tests preserve
the closed `:local_fixture` label rather than collapsing it to `:other`, and the LiveView test
verified one-shot arming.

With `bin/dev` running in fixture mode, Chromium rendered the added controls at 1440x900 and
390x844 with no horizontal overflow or current browser errors. Selecting Failure and sending a
typed message produced no assistant text; the dashboard showed Local fixture / Unavailable / No
first output plus one safe failure. Selecting Delay and sending another typed turn displayed and
spoke `Local fixture response.` The board measured roughly 1.5 seconds to local first output and
reported Deepgram first audio separately. Navigation away from the voice console ended that browser
transport as expected; new rooms exercised subsequent scenarios. Final focused suites and umbrella
gates passed: call engine `115 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures
(3 excluded)`, and Console `12 tests, 0 failures`. Format, warnings-as-errors compilation and
the unused-lock check passed as part of the same root run.

The runtime configuration branches were also checked independently with disposable placeholder
credentials. Fixture mode starts the supervised fixture and does not configure a hosted-model
credential; normal development mode leaves the fixture absent and configures the hosted-model
credential. No credential value was printed or recorded.

The Impeccable finish review returned `ship` with no material fixes after inspecting the current
desktop and mobile captures. It found the fixture controls faithful to the established
three-column desktop board and mobile reading order, with a truthful neutral selected state.
The design documentation review found the controls surface-specific and made no reusable-system
changes.

## Checkpoint 10: embedded Telemetry consumption

The embedded-host acceptance needed a public way to attach to every current call-engine event
without duplicating a private list from the Console reporter. The focused test initially failed
with an undefined `Vxpipe.CallEngine.Telemetry.events/0`. The engine now returns its complete
framework-independent event list from that function. The green test attached an ordinary
Telemetry handler to the list and received a runtime observation using only the call-engine
application.

The engine README now gives a minimal host-owned adapter. It uses a stable handler identifier,
detach-before-attach startup, explicit orderly detach and a local message to a host collector.
The documentation makes the synchronous callback constraint and receiver-side bounded-admission
requirement explicit, along with native-duration conversion. No gateway, Console, Phoenix,
database, authentication, or browser dependency is introduced.

The first root gate run exposed a test-isolation race rather than a runtime failure: async STT
and TTS tests both attach to the process-global provider-failure event, and the TTS no-failure
assertion could receive a valid STT failure emitted by the other test. The owning assertions now
match their `:stt` or `:tts` capability dimension, so they continue to reject a failure from the
subject under test without treating unrelated concurrent engine traffic as their own observation.
The focused embedded consumer and speech-capability run passed `10 tests, 0 failures`. The
subsequent root format, warnings-as-errors compile, default suite and unused-lock gates passed:
call engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`,
and Console `12 tests, 0 failures`.

## Checkpoint 11: Console-owned sample assets

The release asset slice started with two endpoint expectations: the Console root must serve a
configured Vite index with no-store caching, and a missing index must return an explicit 503.
The first test draft had an unqualified response-header helper and did not compile. After fixing
the test itself, the intended red run passed three existing cases and failed both new cases
because the root still returned the placeholder with status 200.

The React/Vite source, package manifest, lockfile and manual instructions now live under the
Console application. Goreman calls the relocated package as the `assets` process, while the same
development ports and Caddy routing remain in place. The Vite production target is Console
`priv/static`. The Console root reads the built index, applies no-store caching, and returns 503
when it is absent; `Plug.Static` serves only the generated `/assets/*` files with immutable
caching. This route work adds no authentication. API-key and join-token responsibilities remain
unchanged. A byte comparison against the pre-move Git objects confirmed that all HTML,
TypeScript, TSX, CSS, test setup and environment-example content moved unchanged; only the
package name, build target, development port variable and path-specific documentation changed.

The endpoint green run passed `5 tests, 0 failures`. The root `assets.test` alias passed the
three existing frontend tests, and the Goreman shell contract passed with the renamed process.
The first root asset alias failed because umbrella `mix cmd` recursively changed into each child
directory; reading `mix help cmd` led to targeting the Console child explicitly with `mix do`.
The corrected alias built 1,902 modules into one index and six generated asset files. Vite warned
that its main bundle exceeds the default chunk-size suggestion; this is unchanged sample code and
does not prevent the release asset outcome.

Local HTTP checks verified a 200 HTML index with no-store caching and a hashed JavaScript asset
with immutable caching. Chromium rendered the unchanged create-room screen through the public
Vite HTTPS origin and through Console's built-asset endpoint at 1440x900; the built endpoint also
rendered at 390x844 with no page errors or horizontal overflow. The initial umbrella-root release
command failed because no umbrella release is defined. Running the release from the Console child
then succeeded, and inspection found the packaged index plus all six generated assets. The docs
now use that verified release command rather than selecting an umbrella release policy here.
The complete root format, warnings-as-errors compile, default suite and unused-lock gates passed:
call engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`,
and Console `13 tests, 0 failures`.

## Checkpoint 12: Phoenix-owned development watcher

The first shell-contract run failed because `bin/dev` still passed `assets` to Goreman. The
focused test now requires that Goreman's selected process list omit that former standalone
frontend entry. The negative-line assertion itself initially returned the final failed `read`
under `set -e`; giving the helper an explicit successful return fixed the test rather than
weakening the behavior it describes.

The Console endpoint now starts `npm run dev` from its Phoenix watcher configuration. The
Procfile no longer declares `assets`, and `bin/dev` starts only the shared BEAM runtime and
Watchman reload helper plus Caddy in its default HTTPS mode. Vite still owns React hot reload,
the same loopback ports, proxy behavior and production build; this change only makes its
lifecycle a child of the Console development endpoint. It supersedes checkpoint 11's separate
Goreman-process detail and does not change the rendered interface.

The green shell contract passed. A fresh `bin/dev` HTTPS run showed only `vxpipe`, `reloader`
and `caddy` as Goreman processes; Vite's ready message and loopback 5174 listener appeared under
the `vxpipe` label after the Console endpoint started. The frontend passed `3 tests, 0 failures`
and its production build completed. Chromium rendered the public HTTPS entry at 1440x900 and
390x844 with no page errors or horizontal overflow. Root format, warnings-as-errors compile,
default suite and unused-lock gates passed with call engine `116 tests, 0 failures (1 excluded)`,
gateway `45 tests, 0 failures (3 excluded)`, and Console `13 tests, 0 failures`.

## Checkpoint 13: Diagnostic socket enablement

HTTP diagnostics already failed closed through `Vxpipe.Console.DiagnosticsEnabled`, but the
endpoint mounted `Phoenix.LiveView.Socket` unconditionally. A direct socket connection could
therefore pass the transport connect boundary even when the corresponding HTTP pages returned
404. The focused endpoint test first failed because the expected Console-owned socket module
did not exist.

`Vxpipe.Console.DiagnosticsSocket` now uses the same enablement predicate as the HTTP Plug.
It refuses disabled connections and accepts an empty, unauthenticated connection when enabled;
the endpoint test also asserts that the diagnostic path mounts this module rather than the
unconditional dependency socket. The focused run passes `6 tests, 0 failures`, including the
existing disabled HTTP 404 and enabled local/remote page checks. A live HTTPS page connected
through the new socket, showed `Collecting`, and produced no browser errors. Root format,
warnings-as-errors compile, default suite and unused-lock gates passed with call engine
`116 tests, 0 failures (1 excluded)`, gateway `45 tests, 0 failures (3 excluded)`, and Console
`14 tests, 0 failures`.

## Checkpoint 14: Vite watcher restart ownership

A live `vxpipe` restart after checkpoint 12 exposed a process-lifecycle gap. Phoenix supervised
the watcher task, but its `npm run dev` child survived BEAM termination and retained port 5174.
Launching the Vite CLI directly removed the npm intermediary but reproduced the orphan because
Vite did not consume the Erlang port's stdin. The replacement watcher then failed and retried
with `Port 5174 is already in use`.

The first Node lifecycle test failed because the expected module was absent. The new
`vite-dev.mjs` entrypoint creates Vite through its programmatic API, consumes stdin, and closes
the server exactly once when stdin ends or the process receives an interrupt/termination signal.
The package's direct development command uses the same entrypoint. A second focused shell test
failed because `bin/dev` did not yet reject a missing `node` executable; the dependency check
now matches the Phoenix watcher command.

After removing the one orphan produced by the superseded implementation, a fresh default-HTTPS
stack started Vite as PID `1966646`. Restarting only Goreman's `vxpipe` process removed that PID;
PID `1966898` then became the sole listener on loopback port 5174 without a port-conflict retry.
This preserves Phoenix ownership across the existing Watchman restart workflow rather than using
process-name cleanup.

The combined asset command initially failed after the Node test passed because Vitest also
discovered the `.test.mjs` file and expected a Vitest suite. Renaming it outside Vitest's default
pattern kept the explicit Node runner without weakening either lane. The final asset suite passes
one Node lifecycle test and three Vitest interface tests, the production bundle completes, and the
shell development contract passes. Chromium reopened the HTTPS voice entry after the restart with
no page errors or horizontal overflow. Root format, warnings-as-errors compile, default suite and
unused-lock gates passed with call engine `116 tests, 0 failures (1 excluded)`, gateway `45 tests,
0 failures (3 excluded)`, and Console `14 tests, 0 failures`.

## Checkpoint 15: Reusable gateway compositions

The mount already covered root/prefixed routing, CORS, host fallthrough, halting and gateway
runtime supervision, but it did not execute the room/session admission path. The added
gateway-only characterization creates a room and issues its participant session below `/voice`
while `Vxpipe.Gateway.HTTP.Supervisor` is absent. It passed on the first run, confirming that no
runtime change was needed. The focused mount suite passes `5 tests, 0 failures`.

The optional standalone path had only source-level configuration evidence. A tagged local-network
test now starts `Vxpipe.Gateway.HTTP.Supervisor` on an ephemeral loopback port, verifies its
configured CORS preflight, creates a room and issues the participant session through real HTTP.
The first run started Bandit but the OTP `:httpc` test client failed before sending because its
internal `:http_util` module was unavailable in this runtime. A bounded raw HTTP/1.1 socket helper
removed that unrelated client dependency; the tagged lane then passed `1 test, 0 failures`.

Together with the existing Console endpoint test—which serves the Console page and gateway health
route through one Phoenix endpoint, observes no standalone HTTP supervisor, and observes live
gateway session/WebRTC supervisors—these checks satisfy the mounted, standalone and shared-listener
composition contracts. The gateway Mix project has no Phoenix or Console dependency.
Root format, warnings-as-errors compile, default suite and unused-lock gates passed with call
engine `116 tests, 0 failures (1 excluded)`, gateway `46 tests, 0 failures (4 excluded)`, and
Console `14 tests, 0 failures`.

## Checkpoint 16: Payload-free bounded reporter queue

The reporter normalized dimensions only after raw Telemetry messages reached its GenServer.
Snapshots were safe, but a suspended reporter retained synthetic text, variables and unique
call/participant/turn identities in its bounded mailbox. The focused red test demonstrated this
with 100 distinct events and failed on the queued-message sentinel check.

After its atomic admission, the synchronous Telemetry callback now performs only bounded
validation and closed-dimension normalization before the local send. The reporter receives
numeric measurements and atoms rather than raw metadata. The green test confirms that neither queued
messages nor the final snapshot contains a sentinel and that 100 unique identities produce one
aggregate key with count 100. The public diagnostics test also renders an event carrying private
fields and finds no sentinel in the HTML. The combined focused run passes `9 tests, 0 failures`.

The first root suite run encountered an unrelated ordering failure in the existing Jido
two-tool-loop test: only the first `tool_started` event reached its assertion. The same focused
test passed ten consecutive repetitions, and the complete umbrella rerun passed with call engine
`116 tests, 0 failures (1 excluded)`, gateway `46 tests, 0 failures (4 excluded)`, and Console
`15 tests, 0 failures`. Root format, warnings-as-errors compile and unused-lock gates also pass.
