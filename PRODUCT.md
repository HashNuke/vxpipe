# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Vxpipe serves people and teams that need a backend for a voice-agent application
or product. Its two intended consumption paths are embedding the runtime in an
Elixir application and operating it as an API-driven service for other stacks.
Docker distribution is planned; the README still labels the image release as
coming soon.

Installation operators use the browser Console to configure tenants and services,
author and publish call specs, and inspect calls. Callers interact with the voice
experiences those teams build, through browser or phone connections.

## Product Purpose

Vxpipe provides the backend runtime for orchestrating voice-agent calls: streaming
speech, model and tool execution, interruptions, transfers between agents and
people, and call visibility. It exists so product teams can build voice
experiences without coupling their application to one model, speech, transport,
or client provider.

Success means developers can run dependable voice-agent workloads through the
same engine whether they embed Vxpipe in an Elixir system or operate it as a
containerized service through its APIs.

## Positioning

Vxpipe is positioned as a more performant, provider-neutral voice AI
orchestration engine. Its engine owns protocol-neutral call behavior while
gateway and provider adapters translate external protocols and services at the
boundaries.

No comparative performance benchmark or claim has been established yet; future
product materials must not invent one.

## Operating Context

- Elixir hosts compose the reusable umbrella applications; the Console owns
  browser presentation and is not a requirement for every embedding host.
- API-driven hosts use tenant-scoped call specs and call admission. Containerized
  distribution remains an intended deployment path rather than a released image.
- Installation operators authenticate to the Console, configure tenant services,
  edit call specs, save immutable revisions, and explicitly publish the revision
  to use for new calls.
- Voice calls compose provider-backed capabilities such as speech recognition,
  model inference, speech synthesis, and speech-to-speech. Supported browser
  media and telephony adapters connect participants to the same call engine.
- Operators inspect ongoing and ended calls through conversation, participant,
  event, variable, and usage views. Missing or partial evidence must remain
  distinguishable from a known result.
- Local development uses `bin/setup` and `bin/dev`. Console samples exercise
  real gateway paths; the shared Storybook provides synthetic UI states without
  requiring provider credentials or a live call.

## Capabilities and Constraints

- The call engine is protocol-neutral and OTP-native.
- Client, media, and provider protocols belong behind adapters rather than in the
  engine's domain model.
- The RTVI adapter targets unmodified RTVI 2.x clients and the RTVI 2.1 feature
  set. Browser samples implement WebRTC/RTVI readiness and typed and spoken
  turns. The target feature set is not a blanket compatibility certification.
  RTVI remains an access mechanism, not Vxpipe's internal object model.
- The runtime includes rooms, participants, capabilities, routing, turn semantics,
  tools, transfers, and protocol-neutral events. Implemented paths include
  interruptions, human handoff, and incoming and outgoing telephony. Support and
  live acceptance depend on the selected provider and transport; a local fixture
  does not establish interoperability with every external service.
- Call specs describe participants, provider/model selections, tools, transfers,
  Call Variables, media policies, and call direction. Console supports visual and
  JSON authoring. Saving a draft and publishing a revision are separate actions;
  editing a call spec does not itself start a call.
- **Call Variables** are typed shared values grouped into sections.
  **Conversation history** contains messages and tool exchanges; **model
  context** is the information supplied to the model. These are distinct from
  the variable store and must not be presented as interchangeable concepts.
- Tenant control-plane storage uses PostgreSQL. API-key authorization, scoped
  join tokens, and installation-operator sessions serve different boundaries.
  Provider credentials are resolved server-side and stay out of portable call
  specs and browser assets.
- The framework-neutral `@vxpipe/core` and UI-focused `@vxpipe/react` packages
  separate call-details state from host URLs, authentication, and transport.
  They are private workspaces, not published npm packages. Their Storybook
  fixtures are demonstrations, not live call evidence.
- The repository is licensed under Apache-2.0, as recorded in `LICENSE`.
  A hosted-service offering, pricing, comparative performance targets, and
  formal compatibility or accessibility commitments remain undecided.

## Brand Commitments

The product name is **Vxpipe**. The existing Console visual system is recorded
in `DESIGN.md`; product-context refreshes do not redefine it. No additional
product-wide voice or brand asset commitments are established by this record.

## Evidence on Hand

- `docs/architecture.md` records protocol and runtime boundaries, implemented
  slices, and remaining proposals; do not treat every architectural target as
  released behavior.
- `docs/tenant-control-plane.md`, `docs/provider-credential-storage.md`, and
  `docs/tenant-telephony-services.md` describe tenant configuration and service
  boundaries. `docs/outgoing-call-runtime.md` records outgoing-call behavior
  and verification evidence.
- `docs/call-spec-editor-guide.md` describes current Console authoring workflows.
  `apps/vxpipe_console/lib/vxpipe/console/router.ex` records current route and
  authentication boundaries.
- `apps/vxpipe_console/assets/` contains Console administration and the browser
  samples using Pipecat's Voice UI Kit and Small WebRTC transport.
- `apps/vxpipe_call_engine/` contains the OTP-native call-engine application.
- `apps/vxpipe_gateway/` contains the client-facing HTTP and protocol boundary.
- `packages/core/`, `packages/react/`, and `.storybook/` provide reusable browser
  components and fixture-based demonstrations. `docs/development/local-development.md`
  records the local setup workflow.
- `LICENSE` establishes the repository license. `README.md` explicitly marks
  the Docker release as forthcoming.
- No verified customer proof, testimonials, comparative performance benchmarks,
  or commercial pricing are established by this record. Future product materials
  must not invent them or turn prototype fixtures into customer evidence.

## Product Principles

1. Keep the orchestration engine independent of voice AI providers.
2. Make embedding in Elixir and API-driven container operation equally credible
   product paths.
3. Preserve explicit protocol boundaries so clients and providers can evolve
   without redefining the engine.
4. Earn the performance position with measured evidence rather than unsupported
   marketing claims.
5. Treat supervision, isolation, and bounded failure handling as product
   behavior, not internal implementation trivia.
