# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Vxpipe serves people and teams that need a backend for a voice-agent application
or product. Elixir developers can embed it as a library in an Elixir project.
Teams using other application stacks can run it as a Docker image and
orchestrate calls through its APIs.

## Product Purpose

Vxpipe provides the backend runtime for orchestrating voice-agent calls. It
exists so product teams can build voice experiences without coupling their
application to one model, speech, transport, or client provider.

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

- Embedded use inside a developer's Elixir supervision tree.
- Containerized use through a Docker image controlled through Vxpipe APIs.
- Browser and mobile voice clients connecting through supported gateway
  protocols and media transports.
- Voice-agent calls composed from provider-backed capabilities such as speech
  recognition, model inference, and speech synthesis.
- Development and interoperability work exercised through the browser samples
  application.

## Capabilities and Constraints

- The call engine is protocol-neutral and OTP-native.
- Client, media, and provider protocols belong behind adapters rather than in the
  engine's domain model.
- The first client adapter targets unmodified RTVI 2.x clients and the RTVI 2.1
  feature set. RTVI is an access mechanism, not Vxpipe's internal object model.
- The engine's intended domain includes rooms, participants, capabilities,
  routing, turn semantics, tools, transfers, and protocol-neutral events.
- The currently implemented end-to-end slice creates a supervised development
  room through the browser playground and gateway. Complete RTVI signaling and
  WebRTC sessions remain future work.
- A hosted-service offering, licensing model, performance target, and formal
  compatibility or accessibility commitments are not yet decided.

## Brand Commitments

The product name is **Vxpipe**. No additional voice, identity, or brand asset
commitments have been established.

## Evidence on Hand

- `docs/architecture.md` records the proposed protocol and runtime architecture,
  the implemented create-room slice, and its verification criteria.
- `apps/vxpipe_console/assets/` provides the Console-owned React and Vite browser
  playground using Pipecat's Voice UI Kit and Small WebRTC transport.
- `apps/vxpipe_call_engine/` contains the OTP-native call-engine application.
- `apps/vxpipe_gateway/` contains the client-facing HTTP and protocol boundary.
- No customer proof, testimonials, comparative benchmarks, pricing, logo, or
  original brand imagery are currently present. Future work must not fabricate
  them.

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
