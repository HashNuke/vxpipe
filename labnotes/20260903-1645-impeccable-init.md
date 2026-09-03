# Impeccable init

## 2026-09-03 — discovery

- The `impeccable` skill was not exposed in the active Codex skill catalog, but
  the existing `.codex/hooks.json` points to a global installation at
  `/home/malt/.agents/skills/impeccable` (version 4.1.3). The installed
  `SKILL.md` and `reference/init.md` are being followed directly.
- `context.mjs` resolved `/home/malt/projects/vxpipe` as the project and
  repository root. It found no existing `PRODUCT.md`, `DESIGN.md`, or surface
  brief, and classified initialization as required.
- Repository evidence supports a `web` platform hypothesis for the current UI:
  `samples/` is a React 19 and Vite 8 browser playground using Pipecat's Voice
  UI Kit and Small WebRTC transport.
- Product documentation describes Vxpipe as a protocol-neutral, OTP-native voice
  runtime. The gateway adapts RTVI 2.x and future external protocols to a call
  engine that owns room, participant, capability, routing, turn, tool, and
  transfer semantics.
- The current implemented product slice creates a supervised development room
  through the browser playground and same-origin gateway. RTVI signaling and a
  complete WebRTC session remain proposed work.
- No logo, image, font, license, testimonial, customer, benchmark, pricing, or
  other proof assets were found in the inspected project paths. This remains a
  repository observation, not confirmed product truth.
- The primary user, product positioning, and durable brand/product constraints
  are material gaps. Per the init workflow, PRODUCT.md will not be written until
  the user confirms or corrects the project-derived hypotheses.

## 2026-09-03 — product interview

- The user confirmed that Vxpipe is for anyone needing a backend for a
  voice-agent application or product.
- Two supported consumption models are product truth: embedding Vxpipe as an
  Elixir library in a developer's Elixir project, or running it as a Docker image
  and orchestrating calls through its APIs.
- The confirmed position is a more performant, provider-neutral voice AI
  orchestration engine. No benchmark exists in the repository, so PRODUCT.md
  preserves the position while explicitly prohibiting fabricated comparative
  evidence.
- The user has not established additional durable constraints. Hosting,
  licensing, formal compatibility, performance targets, accessibility
  commitments, and brand identity beyond the Vxpipe name remain undecided.
- Added root `PRODUCT.md` using Impeccable product schema 1. It records confirmed
  user and positioning facts, repository-supported operating context, current
  implementation maturity, evidence paths, and explicit open decisions. No
  `DESIGN.md` was created because init does not define a visual world.

## 2026-09-03 — workflow defaults

- The user selected comp-first for future new UI surfaces. Added
  `.impeccable/config.json` with `"buildPath": "comp"`; the existing ignored
  `.impeccable/config.local.json` hook-consent setting remains unchanged.
- Live-mode boot against `samples/` resolved the React/Vite application but
  stopped with `context_missing` because there is no `DESIGN.md`. Init must not
  create `DESIGN.md`, so live setup was not forced. `$impeccable document` is the
  tool-recommended next command for recording the incumbent visual system before
  live iteration.
- Added a project-wide `AGENTS.md` rule at the user's request: every UI or web
  application change requires rendered browser inspection with `agent-browser`.
  Headless Chrome is the fidelity path; Lightpanda is the lightweight DOM and
  interaction path. Blocked browser verification must be disclosed.
- Committed only the `AGENTS.md` browser-inspection rule as commit `4589a93`
  (`Require browser inspection for UI changes`). The Impeccable initialization
  artifacts were kept separate and committed in the following checkpoint.
