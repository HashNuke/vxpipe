# Getting Started and example calls

Status: production integration planned; tenant setup/recipe Storybook prototype refined
2026-09-18. Requested 2026-09-16; local specification review recorded below.
Prerequisites: [Call debug console](call-debug-console.md),
[Operator login/admin dashboard](operator-login-and-admin-dashboard.md),
[Platform bootstrap and demo tenant](platform-bootstrap-and-demo-tenant.md), and the existing
[Tenant credentials/platform configuration](tenant-provider-credentials-and-platform-configuration.md).
Sources: [First-use design](developer-console-and-onboarding.md#first-use-flow),
[Operator's Bench](../../DESIGN.md), [inline call specs](../../docs/inline-provider-selections.md).

## Consolidated planning sources — 2026-10-09

Supporting first-use specifications: [Console/onboarding design](developer-console-and-onboarding.md)
and [shared tenant setup](tenant-setup-experience.md). This milestone owns production
home/demo behavior, durable catalog publication and live Console launch acceptance;
prototype and services acceptance do not complete those gates.

The approved shared flow is resumable services → API keys → call specs for every tenant,
with name-only creation, per-tenant progress, optional key creation and optional recipes.
Create & Join Calls grants `calls`; Full Access grants independent `admin` and `calls`,
never installation authority. Reveal a key once; subsequent navigation retains metadata.
Provider choices and capability labels come from the authenticated registry/binding
directory, with explicit model choice and server-validated pinned selections. Each recipe
owns its supported alternatives; adding an STS capability does not automatically qualify
every handoff recipe, and browser recipes do not require telephony.

The companion's fixed provider lists, no-STS statements, retired setup-services route and
early scoped-Telnyx-planned status describe historical revisions. Current registry contracts
and accepted services/speech milestones govern support. No production gate is checked off
by this documentation consolidation.

## Runnable outcome

A first-time developer opens `/`, establishes platform access, creates/adopts the demo tenant,
saves speech/model credentials, installs three working examples, and chooses one to run in the
Vxpipe debug console. A returning developer immediately sees ready examples and current setup
requirements. Refresh, partial failure and restart preserve completed work.

## Contracts

- Replace the current Vxpipe directory at `/`. The user confirmed a persistent setup checklist
  plus sample links, with production behavior by default and explicit demo opt-in on the same image.
- Implement `/` and its setup/example states in the existing React admin application. Build small
  setup/catalog components and complete mocked page states in Console Storybook before connecting
  production workflows. The operator login/code-entry page remains the only server-rendered UI.
- Proposed switch: `VXPIPE_DEMO=1`; unset/blank/`0` disables it in every environment. Other
  non-empty values fail safely. Use only `config/runtime.exs` and document the optional setting
  in visible `env.sample`. This does not switch `MIX_ENV` or weaken production settings.
- Demo off: `/` is a minimal Vxpipe production home without setup/catalog/resource metadata.
  Demo-specific setup/install/launch endpoints reject even direct requests; no hidden anonymous
  sample path survives. Normal authenticated administration/call APIs and separately configured
  inspection/diagnostics keep their own contracts. The flag grants no authority.
- Turning demo mode off retains saved resources and already admitted calls, while disabling new
  demo actions. The same production-built assets support both modes, without seeding on boot.
- Without an operator session, show only the login guidance. Access alone never issues
  a key, claims ownership, creates a tenant, writes credentials or starts a provider call.
- Once authenticated, `/` always shows durable setup state: platform access, demo tenant, three
  capability requirements and per-example installation. Each example's Try action depends on
  its own current prerequisites, not a global wizard-complete boolean. Distinguish missing,
  configured and temporarily unavailable; revalidate authority/readiness when launching.
  Show the next fix action without automatically replacing resources or hiding completed steps.
- Group credential input by provider. Deepgram STT/TTS share one saved binding; Google is the
  default model provider, with existing Zenmux as an explicit supported alternative. Show
  provider/name metadata and capability coverage, not saved secret values. Failed input remains
  locally recoverable without echoing secrets into errors/logs; clear secret fields after submit.
- Distinguish “Tested”, “Saved” and “Successfully used in a call”. **Test credentials** performs a
  read-only provider probe and never persists. **Save** performs local schema validation and
  encrypted persistence without requiring an upstream probe, so providers without a safe test can
  still be configured. A test result applies only to that draft at that time; it does not claim that
  every model, voice or call path works. See the
  [credential testing and storage contract](../../docs/provider-credential-validation.md).
- Catalog entries have stable IDs/version/content digests, purpose, participants, requirement
  metadata and a checked-in inline call spec. Supported selections use the current schema and
  existing provider catalog; no provider keys, route IDs or tenant IDs live in portable templates.
- Initial catalog: voice conversation; agent-to-agent handoff; human handoff with an explicit
  support seat. These reuse implemented flows. First call needs no S3, telephony, external MCP
  endpoint or newly supported provider. Optional prerequisites never masquerade as mandatory.
- Installation is explicit and idempotent per tenant/example/version. Save/publish through Calls,
  store the installed revision/route mapping, and report per-example success/failure. Concurrency
  and lost responses do not duplicate revisions/routes. Preserve user edits; offer an explicit
  new version/copy action instead of overwriting or silently republishing an edited call spec.
- Replace the old managed SampleCall auto-provisioning path for these examples. Reuse/adopt the
  intended development tenant; do not leave a second startup seeder issuing keys/revisions.
  Explicit embedded fixtures stay separate, never an anonymous fallback for hosted setup failure.
- Choosing an example opens its safe published route in the debug console. Actual preparation,
  microphone consent and provider work happen only on the explicit Start action. All preparation
  and secondary-seat actions retain platform/tenant/call authorization; no token goes into URLs.

## Checkpoint 1 — Complete setup through the home page

- [ ] Build and review small setup components, grouped provider forms and complete `/` states in
  Console Storybook: unauthenticated guidance, partial setup, configured, unavailable and demo off.
- [ ] Red-test unset/blank/0/1/invalid demo settings, production-default root behavior and blocked
  direct demo endpoints, unauthenticated guidance, authenticated resumable state, unavailable
  database/keyring, existing demo adoption and partial provider-setup errors.
- [ ] Replace the directory home with the approved React setup page and connect it to the existing
  operator session/demo workflows. Show three capability requirements while avoiding duplicate
  Deepgram key input.
- [ ] Add `VXPIPE_DEMO` runtime handling and optional commented `env.sample` documentation.
  Prove the same source/build toggles surfaces without changing runtime environment, database,
  auth or saved resources; never ship a default platform or provider secret.
- [ ] Verify the browser can finish credential setup, reload and restart without losing progress
  or creating a second tenant/key. Inspect desktop/mobile, keyboard and secret handling.

Exit: a new developer completes the existing setup workflows through an understandable `/`.

## Checkpoint 2 — Install a small reliable example catalog

- [ ] Define/review the three entries and their requirement manifests against current schema,
  provider bindings and existing agent/human-transfer APIs. Use only allowlisted local tools.
- [ ] Red-test first installation, repeat/concurrent installation, partial failure, response loss,
  explicit version updates, edited installed call specs and foreign-tenant route substitution.
- [ ] Implement installation through existing save/publish workflows with durable version/revision
  mapping. Expose per-example status and safe fix/retry actions; never treat a draft as callable.
- [ ] Remove the competing managed-sample startup provisioning path, and update old sample routes
  to an authorized delegate or explicit retired response. No hosted DB/provider failure may reach
  the anonymous in-memory sample fallback. Preserve separately configured library/fixture use.
- [ ] Verify installation and publication survive restart with stable call specs/routes; exercise
  each example's required existing flow using controlled adapters and the tagged browser lane.

Exit: the demo tenant has three discoverable, published examples that can be installed safely again.

## Checkpoint 3 — Choose an example and complete a first call

- [x] Prototype the tenant services-to-recipes journey with disabled missing-service
  states, explicit model choice, recipe diagrams and resumable tenant entry points.
  This is Storybook simulation only; the production tasks below remain open.
- [ ] Build the persistent checklist/gallery with purpose, participant summary, current requirement
  state and one clear action per example. An individually ready example is runnable while another
  remains blocked; temporary lookup failure is unavailable, not permission to reseed anything.
- [ ] Deep-link into the existing debug console with a preselected safe call spec/route.
  Preview does not start media/provider work, and missing requirements link back to their fix.
- [ ] Show useful loading, empty, blocked, provider-rejected and unavailable states; after the
  run preserve results and offer another example or a fresh run without reseeding anything.
- [ ] Prove first-install-to-first-call and returning-user paths on a disposable database;
  restart between setup and call, then verify the exact saved tenant credentials are used.
- [ ] Inspect 360/768/1440 px, light/dark, keyboard/focus, reduced motion, long labels and all
  important states using `agent-browser`. Keep browser tests fixture-backed; real upstream
  interoperability is explicit/tagged and not a new carrier acceptance requirement.
- [ ] Update source-development/docs links and the later container quick-start plan to this
  verified flow. This does not build/publish an image or release the packaging hold.

Exit: the home page teaches a new developer enough to run and understand their first example.

## Acceptance and completion

- [ ] One setup survives refresh/restart/retry without duplicate keys, tenants or revisions.
- [ ] Three capability requirements are satisfied using current supported tenant credentials;
  STT/TTS reuse a binding and no unsupported-provider authentication is introduced.
- [ ] The three real catalog call specs publish, render meaningful previews and run through
  the same debug console; human acceptance uses the existing separately authorized seat.
- [ ] Demo off is the default; same-build on/off behavior and direct-route denial pass. Disabling
  preserves resources/admitted calls. Unauthorized/cross-tenant requests cannot configure or run
  the managed sample; enabled demo mode never enables diagnostic access implicitly.
- [ ] Secrets, missing prerequisites and upstream failures are handled without exposing values,
  claiming unperformed verification or causing implicit provider calls.
- [ ] Focused owning-child tests, frontend checks, common root gates and rendered-browser checks pass.
- [ ] Update this checklist, the index, user-facing setup docs and checkpoint labnotes in small commits.

## Specification review

Local review, 2026-09-16: the new home depends on a functioning debug console and platform setup;
credential entry reuses encrypted tenant storage; manifest-driven installation preserves immutable
history and user changes; conditional routing also guards writes. Shared setup/example components
inherit the existing visual system. The user's follow-up confirms persistent setup tracking,
per-example readiness and production-default/demo-opt-in behavior on one image; `VXPIPE_DEMO=1`
is the proposed concrete switch. All implementation/acceptance boxes remain unchecked.

Amendment review, 2026-09-17: the preceding operator-login milestone replaces platform-key browser
exchange. The Getting Started page is React, uses that operator session, and must be composed from
small components into complete Storybook states before production workflow integration. The
production-default/demo-opt-in and per-example readiness contracts remain unchanged.

Amendment review, 2026-09-18: the user explicitly selected upstream credential validation and a
persisted last-validation timestamp. This supersedes the earlier prohibition on a validation API;
validation remains provider-specific, non-billable, secret-safe and separately testable from a real
call. The Storybook onboarding surface demonstrates the resulting progress and failure states.

Amendment review, 2026-09-21: testing and saving are now explicit independent actions. The test is
read-only and ephemeral; Save does not require provider validation and remains available when no
safe probe exists. This supersedes the coupled pre-save validation and new `last_validated_at`
evidence described by the 2026-09-18 amendment.

Storybook amendment review, 2026-09-18: the user selected provider credential modals,
capability coverage and recipe cards on a second screen, plus resumable per-tenant entry
points on `/admin`. The [tenant setup decision](tenant-setup-experience.md) records
the prototype, rejected alternatives and verification. A checked-in provider/model catalog
supports explicit choices without promising unsupported Google speech integration. These
tenant setup surfaces do not implement the root-home/demo-mode policy or durable catalog
publication; those acceptance gates remain unchecked. Local review only, pending the
user's rendered design review.

Follow-up, 2026-09-18: reuse service onboarding for every tenant. Name-only tenant
creation leads into its own service setup; per-tenant progress is independent.
Telephony remains optional because WebRTC callers can use the same call-spec path.
The added creation/progress/error/new-tenant stories remain frontend simulations.

The subsequent user revision separates onboarding into three pages: Setup services,
Create API Keys, then Setup Call Specs. API keys use the existing independent
`calls` and `admin` grants; sample recipes are confined to the third page. The
[tenant setup decision](tenant-setup-experience.md) records permission evidence,
one-time display semantics and the still-pending production boundaries.

Compact-service refinement, 2026-09-18: the mocked gallery now evaluates readiness
per recipe. The dedicated speech-to-speech preview enables voice conversation;
existing handoff recipes keep their separate speech/language requirements. This
records an explicit prototype compatibility decision, not live audio-provider
support or completed publication/debug-console launch gates. The service picker
and readiness changes are documented in the [tenant setup decision](tenant-setup-experience.md).

Service-picker review, 2026-09-18: onboarding now offers Deepgram, Rime, Google AI
Studio and Telnyx. Other providers are deferred from this prototype UI. Telnyx uses
one connection across AI and telephony sections; its public key is optional for
AI use and required for the telephony credential state. Rime/Telnyx AI execution,
production credential persistence and number routing remain unimplemented gates;
see the [tenant setup decision](tenant-setup-experience.md).

Follow-up, 2026-09-21: the service picker now takes installed capabilities from the provider
registry through the authenticated binding-directory response. Current provider choices and badges
are recorded in the [tenant setup decision](tenant-setup-experience.md); the earlier prototype
speech-to-speech preview and future capability labels were removed.

### Consolidation design review — 2026-10-09

The documentation consolidation received a read-only parallel review of source contracts,
owner requirements and dependency order. Detailed sources remain linked companions;
the existing milestone/index identities, order and completion flags are unchanged.
Historical/proposed obligations are qualified above and in companion provenance banners.
This is specification organization review, separate from runtime implementation progress.
Migration checks and reviewer findings are recorded in the
[consolidation labnote](../20261009-1439-consolidate-doc-history.md).
