# Embedded and container delivery

Status: not implemented; held until the user completes the pre-delivery platform and sample review. Specification review: approved (2026-09-08).
Prerequisites: [Getting Started/example calls](getting-started-and-example-calls.md), including its debug-console and platform-bootstrap prerequisites; [Tenant credentials/platform configuration](tenant-provider-credentials-and-platform-configuration.md); [Context compaction/native fallback](context-compaction-and-native-fallback.md); [Call inspection/debugging](call-inspection-and-debugging.md), and their prerequisites; complete the earlier index entries and the [pre-delivery review hold](index.md#pre-delivery-review-hold) before beginning release work. Whole-call retention deliberately follows delivery as the final milestone.
Sources: [Container/OTP architecture](../architecture.md#configuration-and-container-boundary); [canonical definition boundary](../../labnotes/20260905-0405-call-definition-design.md#canonical-representation); [application ownership](../../labnotes/20260905-0405-call-definition-design.md#umbrella-application-and-ecto-boundaries).
See also the approved [gateway/console boundary](../gateway-console-boundary.md).

## Runnable outcome

Docker is the primary packaged distribution. The same approved call flow runs in
the `vxpipe/vxpipe` image using platform environment settings and encrypted tenant records, and the
components can also be consumed as libraries within an Elixir host application.
Operators can migrate/bootstrap, check readiness, join through configured ingress
and shut down without silently losing or resurrecting work.

## Implementation hold

Do not begin Docker/image packaging as part of the current implementation run. First finish and
exercise the pre-packaging framework and platform through the runnable samples, then let the user
review that working system and choose any fixes or changes. Begin this milestone only after the
user explicitly releases that hold.

## Specification

- Use the organization namespace `vxpipe` for the image, with `vxpipe/vxpipe` as
  the planned image repository. The GitHub source repository remains
  `HashNuke/vxpipe`; image naming does not require a GitHub repository transfer.
  Select and verify the concrete release tag and registry publishing setup during
  packaging implementation; the planned name is not evidence of a published image.
- Build one production artifact that defaults to production behavior. Verify the same image
  with demo mode off and with `VXPIPE_DEMO=1`: only the latter exposes the authenticated setup
  checklist/example catalog. The flag changes no build/runtime environment, database selection,
  TLS or credential protections, and grants no operator access. Disabling demo preserves saved
  resources and already admitted calls. Follow the [first-use contract](../developer-console-and-onboarding.md#first-use-flow).
- Keep the root GitHub README focused on the product and a short Docker quick
  start as the primary installation path. Include verified image/run commands and
  the minimum configuration, secrets, and networking needed to reach a first call.
  Link detailed operations and source-development setup separately. Also explain
  that components can be used as libraries inside users' Elixir applications,
  linking to working host/dependency examples without requiring the Docker image.
- OTP namespaced application settings are canonical at application boundaries; reusable supervisors accept explicit options for embedded hosts. No runtime Mix.env branching or dependency config/<env>.exs assumptions. Read deployment environment only in config/runtime.exs and normalize once.
- Use the platform environment contract from the credential milestone for the image/release runner. JSON call definitions and pinned resource references use the same typed compiler as embedded use. Add no deployment JSON/TOML loader or provider-global fallback. Closed catalogs reject unsupported provider/options and arbitrary module selection.
- Document encrypted tenant provider provisioning through protected operator input and platform keyring injection through the runtime environment. Preserve the existing private MCP credential boundary. Public definitions/plans, errors, logs and image layers never contain credentials; no env-file contents committed. Distinguish provider credentials from gateway-issued hash-only API keys and one-time bootstrap output.
- An embedded engine with inline trusted configuration can run without PostgreSQL; full durable tenant preparation/admission still requires configured persistence. Runtime archive is async, not a database-free admission guarantee. Reusable host app has no dependency on gateway, sample frontend or development Tailscale ingress.
- A host may additionally embed `vxpipe_gateway` without Phoenix or `vxpipe_console`.
  Document its explicit supervision/configuration and mountable Plug/protocol interface,
  using either the host listener or the optional gateway standalone listener. Do not
  start a duplicate listener when the host or console owns ingress. Mounting is an
  integration contract to verify using existing gateway interfaces and minimal adjustments
  if required, not an existing guarantee or a reason to rewrite the gateway.
- `vxpipe_console` / `Vxpipe.Console` owns the Phoenix endpoint, operator pages and
  React sample assets. A standalone console-enabled release composes it with the same
  gateway and serves built assets. Its endpoint mounts/invokes the gateway Plug in-process:
  console and call routes share one HTTP listener/port, with the gateway standalone listener
  disabled and session/connection runtime still running. No internal HTTP proxy hop or
  second gateway listener is part of this topology. Engine/gateway-only hosts do not
  inherit its Phoenix or UI dependencies. Operator diagnostic access remains explicit, not enabled merely
  because the release includes the console. Repo/migrations stay in persistence.
- Configure HTTP binding/origins, database/object storage and provider-reachable telephony ingress explicitly. Development Phoenix/tailnet ingress is not production routing. HTTPS covers signaling/HTTP; WebRTC requires separately configured ICE/media connectivity rather than carrying RTP through the HTTP listener.
- Readiness means required configured engine/gateway/admission services are ready, not merely BEAM alive; keep liveness distinct from an async archive sink outage that must not terminate live calls. Define/test graceful shutdown: stop new admission, bounded session/worker drain, honest incomplete artifacts/history on timeout, deterministic exit; no restart/replay of ended calls.
- Run migrations/bootstrap through documented explicit commands and preserve child dependency ownership/lockfiles. Do not ship dev watchers, sample development servers, local models or credentials inside the production release.

## Implementation checklist

- [ ] Red-test platform env/application-option parity, unavailable tenant credentials, unsupported definition/provider and embedded isolation.
- [ ] Implement the release/image entrypoint, explicit migration/bootstrap commands and runtime health/shutdown integration using the established platform env and tenant DB configuration.
- [ ] Add container build/run instructions with safe platform env and tenant provisioning examples and no real
  secrets; verify licenses and required notices for the pinned direct and transitive
  dependencies before distributing the image.
- [ ] Lead the root README with tested Docker instructions for `vxpipe/vxpipe`,
  retain `HashNuke/vxpipe` as the source repository, and document Elixir library
  consumption with a runnable host example. Keep the source-development quick
  start in the development guide once the Docker quick start replaces it.
- [ ] Smoke-test embedded inline engine and full durable container admission through the same definition fixture.
- [ ] Verify one image in both production-default and explicit demo modes, including direct demo
  endpoint denial when disabled and the authenticated setup-to-debug-console flow when enabled.
- [ ] Smoke-test gateway-only host mounting and its optional standalone listener without
  Phoenix/console dependencies; verify the console-enabled release serves built React
  assets and mounts the same gateway with a single configured ingress owner.
- [ ] Exercise configured HTTPS/signaling and actual WebRTC/telephony media paths separately; document deployment-specific prerequisites.

## Acceptance and failure checks

- [ ] Follow the root README on a clean Docker host through a first configured
  call using the documented image/tag, config, secrets, and network settings.
  Verify its linked Elixir library example runs in a consuming host without
  Docker. README commands must match the built/released artifact and the source
  repository must remain `HashNuke/vxpipe`.
- [ ] Equivalent inline definitions produce equivalent plans/policies through hosted tenant storage and explicit embedded options, without ambient Mix.env behavior in a consuming app.
- [ ] Missing invalid config/secrets fail safely before unauthorized startup; image/build/logs contain no credentials and public strings cannot choose modules/atoms.
- [ ] Embedded engine runs without Ecto/gateway/sample; full container does not claim durable admission when PG is unavailable.
- [ ] Embedded gateway admission/signaling runs without console/Phoenix, using explicitly
  configured processes/routes and no duplicate listener. Equivalent console-hosted routes
  retain the same authentication, CORS and protocol behavior on the one Phoenix HTTP
  listener without an internal HTTP hop or stopping gateway session/connection processes.
- [ ] Embedded hosts can consume engine telemetry without dashboard dependencies.
  Container diagnostic/inspection routes are disabled unless explicitly configured and
  authorized; browser caller tokens never grant operator or cross-tenant access. Missing
  collectors cannot fail established calls, and the image contains no frontend dev server.
- [ ] Readiness/liveness and post-admission archive outage differ; storage failure does not kill established calls.
- [ ] Shutdown rejects new calls, drains permitted work within documented bounds and reports incomplete outcomes without a lossless promise or automatic call replay.
- [ ] Complete final cross-slice regression using definition, private variables, remote tool, human transfer, permitted recording, usage/publication and retention.

## Manual verification

1. Build the image from the implementation checkpoint, inject platform settings and provision synthetic tenant credentials through the established operator workflow.
2. Run documented migrations/bootstrap, inspect safe health responses, prepare and join a call through real configured ingress.
3. Exercise one end-to-end approved flow and compare with an embedded host fixture using equivalent settings.
4. Restart configuration, fail an archive sink during a live call, then gracefully stop the release; inspect correct admission shutdown and truthful persisted artifacts.
5. Verify microphone/HTTPS and WebRTC media connectivity, not only a successful HTTP page load.
6. Run the gateway-only host fixture without Phoenix/console, first mounted and then with
   its standalone listener. Compare joining with the console-enabled container and verify
   the container serves the built sample without a frontend development server.

## Scope boundaries

No hosted control-plane UI, new client protocol, implicit public tailnet exposure, baked deployment secrets, Vxpipe fallback engine, automatic database/S3 incident repair, or implementation of deferred issue features. Deployment-specific choices must be explicit rather than inferred from the development machine.

## Completion and evidence

- [ ] Demonstrate the runnable outcome and every acceptance/failure check above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates).
- [ ] Update this milestone, the index checkbox, relevant architecture/user docs, and
  implementation labnote with actual test/browser/integration evidence in the implementation commit.

Implementation evidence: none yet. Do not mark this slice complete because its specification
has been reviewed.

## Specification review

Reviewed independently by milestone_review_a on 2026-09-08 for approved contracts,
vertical outcome, acceptance/failure coverage, and index/dependency order.
Approved initial draft; embedded/container ownership, typed config, secrets, admission, health/shutdown and media acceptance correct.
The later observability planning update received local review for the added inspection
prerequisite and opt-in diagnostic/embedded reporter acceptance check. It does not imply
the original review agent approved those subsequent edits.
The approved gateway/console split received a further focused specification review for
the engine-only/gateway-only/console-hosted combinations, explicit supervision and single
listener ownership, dependency isolation and built-asset delivery. The existing observable
call prerequisite supplies the shell; no milestone is added or reordered.
This is specification evidence only; implementation and runtime verification remain unchecked.

### Distribution and README review (2026-09-13)

Local review of the user's packaging clarification establishes Docker as the
primary distribution, `vxpipe/vxpipe` as the planned image name, and
`HashNuke/vxpipe` as the unchanged source repository. Elixir library consumption
remains a supported delivery path. The README keeps its product/quick-start role;
packaging acceptance now explicitly covers the Docker instructions and linked
library example. Release tags and runnable commands depend on the actual image
and loader, so they remain implementation gates. This changes documentation and
distribution priorities without changing prerequisites, implementation order,
application boundaries, or the pre-delivery hold. No image has been built or
published by this follow-up, and no implementation checkbox is completed.

### Credential configuration scope review (2026-09-16)

The approved credential milestone supersedes the deployment JSON-loader proposal. Delivery uses
platform env plus encrypted tenant credentials; JSON remains call-definition data. The prerequisite
now includes that configuration cutover. The packaging hold, embedded library boundary and delivery
acceptance remain unchanged. This is a specification correction, not implemented container support.

### Developer setup prerequisite review (2026-09-16)

Local review places the debug console, platform bootstrap and Getting Started slices before
delivery. The image acceptance now covers production-default behavior and explicit demo opt-in
using the same build. Existing embedded boundaries and the pre-delivery user review hold remain
in force. This follow-up adds prerequisite/mode checks, not implementation or image verification.
