# Embedded and JSON-configured container delivery

Status: not implemented. Specification review: approved (2026-09-08).
Prerequisites: [Call retention](call-retention.md); [Context compaction/native fallback](context-compaction-and-native-fallback.md); [Call inspection/debugging](call-inspection-and-debugging.md), and their prerequisites; complete the earlier index entries before release acceptance.
Sources: [Container/OTP architecture](../architecture.md#configuration-and-container-boundary); [canonical definition boundary](../../labnotes/20260905-0405-call-definition-design.md#canonical-representation); [application ownership](../../labnotes/20260905-0405-call-definition-design.md#umbrella-application-and-ecto-boundaries).

## Runnable outcome

The same approved call flow runs embedded in an Elixir host and in a built Docker image using a mounted versioned JSON configuration. Operators can migrate/bootstrap, check readiness, join through configured ingress and shut down without silently losing or resurrecting work.

## Specification

- OTP namespaced application settings are canonical at application boundaries; reusable supervisors accept explicit options for embedded hosts. No runtime Mix.env branching or dependency config/<env>.exs assumptions. Read deployment environment only in config/runtime.exs and normalize once.
- Provide an image/release runner accepting an explicit --config path for one versioned JSON file. Inline definitions and pinned resource references normalize through the same typed compiler/settings as embedded use. Closed registries only; reject unknown versions/unsupported enabled features rather than loading arbitrary modules/atoms.
- Document API-key/provider/MCP secret provisioning through runtime environment/mounted secret references/private configuration boundaries. Public definitions/plans, errors, logs and image layers never contain credentials; no env-file contents committed. Distinguish provider credentials from gateway-issued hash-only API keys and one-time bootstrap output.
- An embedded engine with inline trusted configuration can run without PostgreSQL; full durable tenant preparation/admission still requires configured persistence. Runtime archive is async, not a database-free admission guarantee. Reusable host app has no dependency on gateway, sample frontend, Caddy or Tailscale.
- Configure HTTP binding/origins, database/object storage and provider-reachable telephony ingress explicitly. Development Caddy/tailnet ingress is not production routing. HTTPS reverse proxy covers signaling/HTTP; WebRTC requires separately configured ICE/media connectivity, not proxying RTP through Caddy.
- Readiness means required configured engine/gateway/admission services are ready, not merely BEAM alive; keep liveness distinct from an async archive sink outage that must not terminate live calls. Define/test graceful shutdown: stop new admission, bounded session/worker drain, honest incomplete artifacts/history on timeout, deterministic exit; no restart/replay of ended calls.
- Run migrations/bootstrap through documented explicit commands and preserve child dependency ownership/lockfiles. Do not ship dev watchers, sample development servers, local models or credentials inside the production release.

## Implementation checklist

- [ ] Red-test application-option/JSON normalization parity, missing config/secrets, unsupported version/adapter and embedded isolation.
- [ ] Implement versioned config loader, release/image entrypoint, explicit migration/bootstrap commands and runtime health/shutdown integration.
- [ ] Add container build/run instructions with safe mounted config examples and no real
  secrets; verify licenses and required notices for the pinned direct and transitive
  dependencies before distributing the image.
- [ ] Smoke-test embedded inline engine and full durable container admission through the same definition fixture.
- [ ] Exercise configured HTTPS/signaling and actual WebRTC/telephony media paths separately; document deployment-specific prerequisites.

## Acceptance and failure checks

- [ ] Equivalent OTP and JSON inputs produce equivalent plans/policies without ambient Mix.env behavior in a consuming app.
- [ ] Missing invalid config/secrets fail safely before unauthorized startup; image/build/logs contain no credentials and public strings cannot choose modules/atoms.
- [ ] Embedded engine runs without Ecto/gateway/sample; full container does not claim durable admission when PG is unavailable.
- [ ] Embedded hosts can consume engine telemetry without dashboard dependencies.
  Container diagnostic/inspection routes are disabled unless explicitly configured and
  authorized; browser caller tokens never grant operator or cross-tenant access. Missing
  collectors cannot fail established calls, and the image contains no Vite dev server.
- [ ] Readiness/liveness and post-admission archive outage differ; storage failure does not kill established calls.
- [ ] Shutdown rejects new calls, drains permitted work within documented bounds and reports incomplete outcomes without a lossless promise or automatic call replay.
- [ ] Complete final cross-slice regression using definition, private variables, remote tool, human transfer, permitted recording, usage/publication and retention.

## Manual verification

1. Build the image from the implementation checkpoint and mount a synthetic configuration plus separately provisioned secrets.
2. Run documented migrations/bootstrap, inspect safe health responses, prepare and join a call through real configured ingress.
3. Exercise one end-to-end approved flow and compare with an embedded host fixture using equivalent settings.
4. Restart configuration, fail an archive sink during a live call, then gracefully stop the release; inspect correct admission shutdown and truthful persisted artifacts.
5. Verify microphone/HTTPS and WebRTC media connectivity, not only a successful HTTP page load.

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
This is specification evidence only; implementation and runtime verification remain unchecked.
