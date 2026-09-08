# Call-definition implementation milestones

Status: 21 milestone specifications; implementation has not started. The earlier behavior
contracts were independently reviewed; the user-approved Jido mechanism update awaits
focused follow-up review in the affected specifications.
Source baseline: `9eb35a4` (approved design), plus the user-approved Morse and internal
MCP-library additions and Jido runtime selection documented during planning on 2026-09-08.
Jido AI replaces custom agent-loop work and Jido MCP replaces direct client-library work
inside existing milestones; the count and order do not change.

## How to use this index

Implement in the order below. Each entry is a runnable vertical slice, not a horizontal
module-building phase. Dependencies inside a milestone are its direct prerequisites;
the list gives a conservative total order, even where independent work is possible.
Read the [call-definition design](../../labnotes/20260905-0405-call-definition-design.md),
[decision register](../call-definition-gap-review.md), and [architecture](../architecture.md).
Current approved decisions supersede historical proposals retained in the labnote.

Keep every implementation checkbox unchecked until the corresponding work and evidence
exist. A reviewed specification is not implemented functionality. Update task boxes in the
milestone and then its index entry in the same implementation checkpoint. Record partial
progress without claiming the entire milestone is complete.

## Ordered implementation checklist

1. [ ] [Definition-driven one-agent call](definition-driven-call.md) — Compile a typed, pinned plan and run its text/audio and host-tool conversation through Jido AI.
2. [ ] [Local Morse-code audio providers](morse-code-audio-providers.md) — Exercise real audio ingress/egress with deterministic text-to-tones and tones-to-text providers.
3. [ ] [Call Variables and private tool projections](call-variables-and-tool-visibility.md) — Read/update sectioned variables through tools without exposing private data.
4. [ ] [Conversation during background tools](background-tool-conversation.md) — Keep conversation responsive while a submitted tool finishes.
5. [ ] [Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md) — Save immutable definitions and bootstrap tenant-scoped administrative access.
6. [ ] [Prepared calls and single-use joining](prepared-call-admission.md) — Prepare in PostgreSQL, then start exactly one live call when its caller joins.
7. [ ] [Asynchronous call history and variable snapshots](asynchronous-call-history.md) — Archive permitted events without putting PostgreSQL in the live-call critical path.
8. [ ] [Jido MCP integration and conformance](mcp-client-library.md) — Verify Jido MCP through a thin policy adapter, Jido Action exposure, and version-pinned reference/conformance server.
9. [ ] [Remote MCP tools in a live call](remote-mcp-tools.md) — Run a validated, tenant-configured remote tool while talking.
10. [ ] [Opening audio and call lifecycle](opening-audio-and-call-lifecycle.md) — Play optional opening audio, greet, and enforce approved live-call timers.
11. [ ] [Allowlisted agent-to-agent transfers](agent-transfers.md) — Transfer responsibility between agent participants without losing variables.
12. [ ] [Live mixing and presence-driven media policy](live-mixing-and-media-policy.md) — Route/mix multiple participants live and enforce transcript/audio denials.
13. [ ] [Private briefing and human web acceptance](human-web-transfers.md) — Privately brief a destination, accept over web control, then bridge human-only audio.
14. [ ] [Telnyx calls and phone transfers](telnyx-calls.md) — Connect verified telephony legs through the same admission and transfer contracts.
15. [ ] [Twilio through the common telephony contract](twilio-calls.md) — Prove a second provider fits without changing participant definitions or room control.
16. [ ] [Permitted live recordings streamed to S3](streaming-recordings.md) — Record live mix and separate tracks without blocking participants or saving denied intervals.
17. [ ] [Usage, cost observations, and billing enrichment](usage-and-billing-observations.md) — Inspect honest call/participant/turn usage even when prices are unavailable.
18. [ ] [Versioned call-details publications](call-details-publications.md) — Publish immutable timestamp-named details and honest completion state after calls end.
19. [ ] [Whole-call retention and deletion](call-retention.md) — Sweep expired calls, deleting external artifacts before database records.
20. [ ] [Context compaction and supported LLM fallback](context-compaction-and-native-fallback.md) — Continue long conversations within model limits without changing tool or privacy authority.
21. [ ] [Embedded and JSON-configured container delivery](embedded-and-container-delivery.md) — Run the same platform through host application settings or a standalone JSON-configured image.

## Common implementation and verification gates

Every milestone inherits these requirements; its own checklist adds the slice-specific gates.

- [ ] For that milestone, write the smallest failing project-owned behavior test first;
  run it red, implement it green, then refactor. Documentation/configuration-only work
  may skip red as described in [AGENTS.md](../../AGENTS.md).
- [ ] Run focused tests from the owning umbrella child and record commands/results in
  the milestone's implementation evidence. Do not test dependency-guaranteed behavior.
- [ ] Run from the umbrella root: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix test`, and
  `mix deps.unlock --check-unused`. Keep real provider/network tests in a tagged
  integration lane excluded from the default suite.
- [ ] Inspect any changed sample UI in a rendered browser using `agent-browser`,
  including relevant responsive states. Follow applicable UI skills at implementation
  time; planning these documents is not a UI implementation.
- [ ] Preserve the existing runnable sample and embedded use, relevant docs and lockfiles.
  Keep secrets, raw auth headers, and sensitive fixture data out of commits/logs.
- [ ] Commit each coherent authorized implementation checkpoint with its tests, docs,
  milestone task updates, and labnote evidence. Document any blocked external checks honestly.

The boxes above describe repeated gates for each milestone, not already-executed tests
or a substitute for the individual milestone checklists. The final implementation agent
may mark this common list complete only after the gates have been met for all milestones.

The descriptive filenames and titles are stable identifiers. This numbered checklist alone
owns ordering; insert or move entries here without renaming milestone files.

## Scope and dependency rules

The current playground already creates rooms and supports a single human/agent text/audio
path, streaming model output, hosted speech services, and engine-owned tool execution.
It does not implement the reviewed definition compiler, durable admission, Call Variables,
remote MCP, multi-party mixer, telephony, or storage system. Reuse working code; do not
recreate applications or label existing primitives as newly implemented.

Early milestones expose only their implemented subset. Reject unsupported enabled features
explicitly; never silently ignore a presence/privacy rule, auth requirement, or provider
option to make a demo pass. A later slice expands support without changing the final approved
contracts. Trusted embedded/development fixtures are not public production admission.

The engine owns room/participant/capability lifecycles and protocol-neutral contracts.
Use Jido AI's standalone ReAct runtime for ordinary agent model/tool iteration and Jido
Action for the agent-visible tool contract. ReqLLM remains Jido AI's provider layer rather
than Vxpipe's custom orchestration surface. Vxpipe still owns identities, authorization,
stream/TTS projection, interruption, submitted background workers and room lifecycle; do
not introduce Jido AgentServer as a competing lifecycle authority in the initial plan.
Introduce `vxpipe_calls` for application workflows, `vxpipe_persistence` for Ecto/Repo,
and `vxpipe_artifacts` for object storage only in their owning milestones. The gateway
authenticates/translates; it does not gain direct Repo or provider orchestration ownership.
The separate `vxpipe_mcp` internal library is a thin adapter around the selected
`jido_mcp` integration, not a custom protocol/client codebase. Jido MCP owns its protocol,
client pooling and transport integration through its public API; which transitive library it
uses is not a Vxpipe architecture decision. The wrapper configures supervision, policy
enforcement and result mapping without room, tenant-selection, Repo or gateway dependencies.
Vxpipe does not depend on or call Jido MCP's transitive client library directly. Its standalone
integration/conformance checkpoint precedes live-call integration and targets
MCP `2025-11-25`, replacing the earlier `2026-07-28` profile. No custom-client fallback.
Preserve dependency direction in child `mix.exs` files.

Runtime variables acknowledge local acceptance and asynchronous archival handoff, never
database commit. PostgreSQL remains required for configured admission. Archive subscribers
must respect source-interval privacy before queueing and at sinks; no durable/no-loss
guarantee follows from an in-memory message. Do not add a queue dependency or automatic
post-incident repair framework merely to complete this plan.

Deferred items are not checklist prerequisites: same-call caller reconnection (R07),
automatic tool retries/idempotency (R16), general MCP document inspection (R24),
server-requested MCP interactions (R25), explicit cancellation, late external events,
wait music, voicemail delivery, general redaction, and OAuth onboarding. See
[the decision register](../call-definition-gap-review.md) and [issues](../issues/).
The optional Morse-code providers are deterministic tone encoders/decoders, not speech ML
models. No local VAD/speech models, graph engine, new client protocol, or Vxpipe
provider-fallback chain.

## Decision coverage

This is a coverage map, not another approval or implementation checklist.

- **Definition-driven one-agent call**: G1/G2; R10, R47; selected Jido AI/Jido Action agent loop.
- **Local Morse-code audio providers**: optional local verification capabilities requested during planning.
- **Call Variables and private tool projections**: G3/G5; R17, R18.
- **Conversation during background tools**: G4; R14–R16, R29.
- **Tenant definitions and API-key administration**: G2/G10; R01–R04, R39.
- **Prepared calls and single-use joining**: G2/G10; R05–R10, R39, R40.
- **Asynchronous call history and variable snapshots**: G5/G11; R18, R41.
- **Jido MCP integration and conformance**: selected Jido integration surface, thin policy boundary, Jido Action exposure and reference validation; R22, R23, R26, R49.
- **Remote MCP tools in a live call**: G4/G6; R14–R16, R22–R26, R49.
- **Opening audio and call lifecycle**: G7; R11, R12, R27–R31.
- **Allowlisted agent-to-agent transfers**: G8; R13, R33, R35, R36.
- **Live mixing and presence-driven media policy**: G9; R38.
- **Private briefing and human web acceptance**: G8; R33–R38.
- **Telnyx calls and phone transfers**: G2/G8/G10; R13, R32–R40.
- **Twilio through the common telephony contract**: G8/G10; R13, R32–R40.
- **Permitted live recordings streamed to S3**: G9/G11; R18, R38, R41.
- **Usage, cost observations, and billing enrichment**: G12; R44–R46.
- **Versioned call-details publications**: G11; R42, R43.
- **Whole-call retention and deletion**: G5; R19–R21.
- **Context compaction and supported LLM fallback**: G13; R47, R48, R50.
- **Embedded and JSON-configured container delivery**: Container/OTP boundary; complete approved scope.

## Specification review evidence

Each milestone was dispatched to a review agent after its draft was created. Reviews
checked vertical outcomes, approved-source fidelity, missing acceptance/failure cases and
index/dependency order. Material findings were corrected and re-reviewed. All 21 reviews
are complete; review approval is separate from the unchecked implementation boxes.

| Milestone | Review status | Evidence |
| --- | --- | --- |
| [Definition-driven one-agent call](definition-driven-call.md#specification-review) | Follow-up pending | Original behavior approved by milestone_review_a; later Jido AI/Jido Action mechanism is user-approved and awaits focused independent review. |
| [Local Morse-code audio providers](morse-code-audio-providers.md#specification-review) | Approved | milestone_review_a; real audio, independent fixtures, bounded streaming and explicit transport limits. |
| [Call Variables and private tool projections](call-variables-and-tool-visibility.md#specification-review) | Follow-up pending | Original behavior approved by milestone_review_b; Jido Action mechanism is user-approved and awaits focused independent review. |
| [Conversation during background tools](background-tool-conversation.md#specification-review) | Follow-up pending | Original behavior approved by milestone_review_c; Jido ReAct/Action mechanism is user-approved and awaits focused independent review. |
| [Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md#specification-review) | Approved | milestone_review_a; Separated reusable revision metadata from per-call plan/credential resolution; excluded credentials and leases from revisions/routes; focused re-review approved. |
| [Prepared calls and single-use joining](prepared-call-admission.md#specification-review) | Approved | milestone_review_b; Added pinned join mapping, occurrence timestamps, pre/post-admission token semantics, credential/Origin separation and nonblocking lifecycle handoff; re-review approved. |
| [Asynchronous call history and variable snapshots](asynchronous-call-history.md#specification-review) | Approved | milestone_review_c; Added subscriber crash/saturation isolation, rejected/stale baseline snapshot cases and honest draining; re-review approved. |
| [Jido MCP integration and conformance](mcp-client-library.md#specification-review) | Follow-up pending | Original behavior/profile approved by milestone_review_a; Jido MCP dependency and Jido Action integration are user-approved and await focused independent review. |
| [Remote MCP tools in a live call](remote-mcp-tools.md#specification-review) | Follow-up pending | Original live-call behavior and policy boundary approved by milestone_review_a; later Jido MCP mechanism is user-approved and awaits focused independent review. |
| [Opening audio and call lifecycle](opening-audio-and-call-lifecycle.md#specification-review) | Approved | milestone_review_b; Added caller-only playback, readiness cleanup/duplicate greeting, explicit idle exclusions and pinned duration hierarchy tests; re-review approved. |
| [Allowlisted agent-to-agent transfers](agent-transfers.md#specification-review) | Approved | milestone_review_c; Specified history modes, precommit destination silence/source continuity, empty-list and total-deadline races; re-review approved. |
| [Live mixing and presence-driven media policy](live-mixing-and-media-policy.md#specification-review) | Approved | milestone_review_a; Distinguished omitted policy fields from denied omitted route sources and added fail-closed policy-apply admission/bridge checks; re-review approved. |
| [Private briefing and human web acceptance](human-web-transfers.md#specification-review) | Approved | milestone_review_b; Added bidirectional private-lane isolation, transcript/snapshot restrictions and early-acceptance sequencing tests; re-review approved. |
| [Telnyx calls and phone transfers](telnyx-calls.md#specification-review) | Approved | milestone_review_c; Added dial-only dynamic source, no inbound re-admission for transfer callbacks, PG-outage runtime correlation and provider-reachable ingress checks; re-review approved. |
| [Twilio through the common telephony contract](twilio-calls.md#specification-review) | Approved | milestone_review_a; Approved initial draft; shared contract order and separate vendor verification, media/acceptance/failure parity sufficient. |
| [Permitted live recordings streamed to S3](streaming-recordings.md#specification-review) | Approved | milestone_review_b; Corrected provable egress vs remote-playout boundary, room manifest identity and terminal-manifest outage guarantees; re-review approved. |
| [Usage, cost observations, and billing enrichment](usage-and-billing-observations.md#specification-review) | Approved | milestone_review_c; Added final delta vs cumulative arithmetic, stale provenance handling and no prohibited STT for accounting; re-review approved. |
| [Versioned call-details publications](call-details-publications.md#specification-review) | Approved | milestone_review_a; Approved initial draft; clarified lifecycle/direction/route/plan digest in publication contents. |
| [Whole-call retention and deletion](call-retention.md#specification-review) | Approved | milestone_review_b; Added tenant/call object deletion isolation and inherited vs explicit policy-change checks; re-review approved. |
| [Context compaction and supported LLM fallback](context-compaction-and-native-fallback.md#specification-review) | Approved | milestone_review_c; Added failed/stale compaction preservation, merged-input budget rechecks, limited summarizer authority and unsupported fallback validation; re-review approved. |
| [Embedded and JSON-configured container delivery](embedded-and-container-delivery.md#specification-review) | Approved | milestone_review_a; Approved initial draft; embedded/container ownership, typed config, secrets, admission, health/shutdown and media acceptance correct. |

## Planning verification

Verified on 2026-09-08:

- All 21 milestone files have specifications, prerequisites, implementation task lists,
  acceptance/failure checks and manual verification steps. Earlier behavior contracts have
  independent review evidence; the five Jido-updated specifications are marked for focused
  follow-up review rather than presenting the new mechanism as already reviewed.
- The 21 index entries match the files exactly; filenames/titles have no ordering numbers.
  All explicit prerequisites occur earlier in the index; no dependency cycles were found.
- All milestone implementation/verification boxes remain unchecked, along with the index
  and common gates. No runtime work is claimed by specification approval or dependency
  selection.
- Relative file/heading links, decision coverage and Markdown task-list structure pass
  focused checks. All 50 decision IDs are accounted for: 45 resolved, four deferred and
  one superseded. Deferred features have not become implementation prerequisites.
- The three design sources retain all 43 existing fenced examples unchanged from the
  baseline; their 19 JSON examples still parse. Diff/terminology/path checks pass.
- The pre-Jido cross-index audit by milestone_review_c found no remaining coverage or
  dependency findings in that baseline. The Jido follow-up review remains explicitly open.
- The Jido selection changes implementation mechanisms, not the approved MCP product
  profile, count, filenames or order. Jido MCP owns its internal client implementation;
  Vxpipe validates only the effective public integration and its own policy boundary.

This checkpoint changes documentation only. No runtime, browser, provider, official
conformance, or umbrella test execution is claimed; those remain implementation gates.
The compaction execution/model choice and explicitly identified provider/encoding
particulars still require selection at implementation time.
