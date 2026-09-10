# Call-definition implementation milestones

Status: 24 milestone specifications: 11 complete and 13 incomplete. Milestone 12, remote MCP
tools in a live call, is the next implementation slice. Its protocol, policy, catalog, and binding
foundations exist; the completed ReqLLM runtime now supplies the model/tool execution prerequisite.
The earlier behavior contracts have completed focused review.
Source baseline: `9eb35a4` (approved design), plus the user-approved Morse and internal
MCP-library additions and historical Jido runtime selection documented during planning on
2026-09-08. The 2026-09-10 [runtime decision](../reqllm-agent-runtime.md) inserts a separate
ReqLLM-based agent-runtime package before live MCP tools; ExMCP continues to supply the
protocol client behind `vxpipe_mcp`. The subsequent user-requested
observability additions introduce an early observable sample call and later call inspection;
the original milestones retain their filenames and relative order.
The approved [gateway/console boundary](../gateway-console-boundary.md) keeps the gateway
reusable and assigns Phoenix/dashboard/sample ownership to `vxpipe_console` /
`Vxpipe.Console`. It changes these slices' application ownership, not their count or order.

## How to use this index

Implement in the order below. Product/operator entries describe runnable vertical slices;
the standalone MCP client/conformance entry is an enabling checkpoint for its live-call
slice, not an end-to-end call feature. Dependencies inside a milestone are its direct prerequisites;
the list gives a conservative total order, even where independent work is possible.
Read the [call-definition design](../../labnotes/20260905-0405-call-definition-design.md),
[decision register](../call-definition-gap-review.md), and [architecture](../architecture.md).
Current approved decisions supersede historical proposals retained in the labnote.

Keep every implementation checkbox unchecked until the corresponding work and evidence
exist. A reviewed specification is not implemented functionality. Update task boxes in the
milestone and then its index entry in the same implementation checkpoint. Record partial
progress without claiming the entire milestone is complete.

## Ordered implementation checklist

1. [x] [Definition-driven one-agent call](definition-driven-call.md) — Compile a typed, pinned plan and run its text/audio and host-tool conversation through the selected agent runtime.
2. [x] [Observable sample call](observable-sample-call.md) — Run a sample conversation and inspect live timing, provider failures and VM health on a separate dashboard.
3. [x] [Local Morse-code audio providers](morse-code-audio-providers.md) — Exercise real audio ingress/egress with deterministic text-to-tones and tones-to-text providers.
4. [x] [Call Variables and private tool projections](call-variables-and-tool-visibility.md) — Read/update sectioned variables through tools without exposing private data.
5. [x] [Conversation during background tools](background-tool-conversation.md) — Keep conversation responsive while a submitted tool finishes.
6. [x] [Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md) — Save immutable definitions and bootstrap tenant-scoped administrative access.
7. [x] [Prepared calls and single-use joining](prepared-call-admission.md) — Prepare in PostgreSQL, then start exactly one live call when its caller joins.
8. [x] [Asynchronous call history and variable snapshots](asynchronous-call-history.md) — Archive permitted events without putting PostgreSQL in the live-call critical path.
9. [x] [Call inspection and debugging](call-inspection-and-debugging.md) — Inspect an authorized live or ended call's timeline, permitted snapshots, timings and archival gaps.
10. [x] [MCP client integration and conformance](mcp-client-library.md) — Verify ExMCP through a thin policy adapter and version-pinned reference/conformance server, independently of Jido.
11. [x] [ReqLLM agent runtime](reqllm-agent-runtime.md) — Build and adopt the reusable streamed model/tool loop without Jido.
12. [ ] [Remote MCP tools in a live call](remote-mcp-tools.md) — Run a validated, tenant-configured remote tool while talking.
13. [ ] [Opening audio and call lifecycle](opening-audio-and-call-lifecycle.md) — Play optional opening audio, greet, and enforce approved live-call timers.
14. [ ] [Allowlisted agent-to-agent transfers](agent-transfers.md) — Transfer responsibility between agent participants without losing variables.
15. [ ] [Live mixing and presence-driven media policy](live-mixing-and-media-policy.md) — Route/mix multiple participants live and enforce transcript/audio denials.
16. [ ] [Private briefing and human web acceptance](human-web-transfers.md) — Privately brief a destination, accept over web control, then bridge human-only audio.
17. [ ] [Telnyx calls and phone transfers](telnyx-calls.md) — Connect verified telephony legs through the same admission and transfer contracts.
18. [ ] [Twilio through the common telephony contract](twilio-calls.md) — Prove a second provider fits without changing participant definitions or room control.
19. [ ] [Permitted live recordings streamed to S3](streaming-recordings.md) — Record live mix and separate tracks without blocking participants or saving denied intervals.
20. [ ] [Usage, cost observations, and billing enrichment](usage-and-billing-observations.md) — Inspect honest call/participant/turn usage even when prices are unavailable.
21. [ ] [Versioned call-details publications](call-details-publications.md) — Publish immutable timestamp-named details and honest completion state after calls end.
22. [ ] [Whole-call retention and deletion](call-retention.md) — Sweep expired calls, deleting external artifacts before database records.
23. [ ] [Context compaction and supported LLM fallback](context-compaction-and-native-fallback.md) — Continue long conversations within model limits without changing tool or privacy authority.
24. [ ] [Embedded and JSON-configured container delivery](embedded-and-container-delivery.md) — Run the same platform through host application settings or a standalone JSON-configured image.

## Common implementation and verification gates

Every milestone inherits these requirements; its own checklist adds the slice-specific gates.

- [ ] For that milestone, write the smallest failing project-owned behavior test first;
  run it red, implement it green, then refactor. Documentation/configuration-only work
  may skip red as described in [AGENTS.md](../../AGENTS.md).
- [ ] Run focused tests from the owning umbrella child and record commands/results in
  the milestone's implementation evidence. Do not test dependency-guaranteed behavior.
- [ ] Run from the umbrella root: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
  `mix deps.unlock --check-unused`. Keep real provider/network tests in a tagged
  integration lane excluded from the default suite.
- [ ] Inspect any changed sample UI in a rendered browser using `agent-browser`,
  including relevant responsive states. Follow applicable UI skills at implementation
  time; planning these documents is not a UI implementation.
- [ ] Preserve the existing runnable sample and embedded use, relevant docs and lockfiles.
  Keep secrets, raw auth headers, and sensitive fixture data out of commits/logs.
- [ ] Once the observability/inspection slices are available, extend their measurements
  and projections for the feature being implemented: relevant latency/outcomes, lifecycle,
  queue pressure and safe correlation. Verify success and a controlled failure/gap without
  leaking payloads or blocking live work. Unsupported measurements stay explicit; do not
  wait for the usage/billing milestone to add ordinary operational visibility.
- [ ] Commit each coherent authorized implementation checkpoint with its tests, docs,
  milestone task updates, and labnote evidence. Document any blocked external checks honestly.

The boxes above describe repeated gates for each milestone, not already-executed tests
or a substitute for the individual milestone checklists. The final implementation agent
may mark this common list complete only after the gates have been met for all milestones.

The descriptive filenames and titles are stable identifiers. This numbered checklist alone
owns ordering; insert or move entries here without renaming milestone files.

## Scope and dependency rules

The current playground already creates rooms and supports durable admission, a single human/agent
text/audio path, streaming model output, hosted speech services, engine-owned tool execution,
room-scoped Call Variables with private model/client projections, asynchronous call history, and
call inspection. It does not implement live remote MCP, a multi-party mixer, telephony, streaming
recordings, billing enrichment, or whole-call retention. Reuse working code; do not recreate
applications or label existing primitives as newly implemented.

Early milestones expose only their implemented subset. Reject unsupported enabled features
explicitly; never silently ignore a presence/privacy rule, auth requirement, or provider
option to make a demo pass. A later slice expands support without changing the final approved
contracts. Trusted embedded/development fixtures are not public production admission.

The engine owns room/participant/capability lifecycles and protocol-neutral contracts.
After the intermediate runtime milestone, one supervised `Vxpipe.AgentRuntime` session is
the inference child of each active agent participant. The separate `vxpipe_agent_runtime`
child owns ReqLLM conversation state, exact data-backed tool projection, repeated model/tool
rounds, streaming/cancellation and neutral runtime events. Call Engine owns identities, turn
serialization and queueing, authorization, private tool execution, stream/TTS projection,
interruption policy, submitted tool workers, transfers, variables and room lifecycle.
The package neither becomes a participant authority nor gains room, tenant, MCP, persistence,
gateway, or client-protocol dependencies.
Introduce `vxpipe_calls` for application workflows, `vxpipe_persistence` for Ecto/Repo,
and `vxpipe_artifacts` for object storage only in their owning milestones. The gateway
authenticates/translates; it does not gain direct Repo or provider orchestration ownership.
The separate `vxpipe_mcp` internal library depends directly on `ex_mcp`, not the agent
runtime or domain applications. ExMCP owns protocol/transport lifecycle through
public APIs. The wrapper configures supervision, scoped client reuse, policy enforcement
and result mapping without room, tenant-selection, Repo or gateway dependencies. Its
standalone integration/conformance checkpoint targets MCP `2025-11-25`, replacing the
earlier `2026-07-28` profile. No custom-client fallback.
Call Engine connects an activation's immutable private bindings to the agent runtime's narrow
submit-only executor contract. Every tool operation runs in an independently supervised
Call Engine worker. Local bindings default to blocking later caller conversation and may
explicitly select `non_blocking`; this admission policy never changes worker placement. Before
each model generation the runtime receives a bounded payload-free projection of authoritative
pending invocations. The model receives only exact local string names, permitted descriptions,
and pinned JSON schemas. Endpoint, credential and remote-operation selectors remain private.
No externally driven atom/module generation, private dependency APIs, or generic model-visible
endpoint/tool dispatcher is an acceptable workaround. Preserve dependency direction in child
`mix.exs` files. The completed Jido-backed slices remain historical evidence; milestone 11
proved parity, removed Jido, and left no second production loop behind.

The two observability slices deliver separate operator interfaces without expanding the
voice console. The early slice introduces the approved Phoenix shell, `vxpipe_console` /
`Vxpipe.Console`, owning endpoint/dashboard/sample assets. The existing `vxpipe_gateway`
retains reusable Plug/protocol/connection ownership with no Phoenix/UI dependency; its
planned supported mounting interface, explicit supervision/configuration and optional
standalone listener require implementation and verification. Do not regenerate or rename
the gateway: add the console around its existing interfaces, making only minimal mounting
or configuration adjustments if required. The console depends on gateway public interfaces
and, when introduced by its owning prerequisite, Calls public APIs. Its Phoenix endpoint
mounts/invokes the gateway Plug in-process on one shared HTTP listener/port, disabling
only the gateway standalone listener while retaining session/connection supervision.
No internal HTTP proxy hop or second gateway listener is needed; the standalone listener
is an alternative embedding mode. React remains the sample implementation under
Console asset ownership; Phoenix supervises its esbuild watcher and serves the generated
assets on that shared listener. Moving asset ownership does not mean rewriting the sample
in LiveView or operating a separate frontend server.
Engine/gateway instrumentation is independent of its reporter/UI, and inspection uses
authorized live projections and Calls history rather than console/gateway Repo access.
LiveDashboard remains the selected VM dashboard; this slice adds no Console-page authentication,
and deployment exposure remains an application concern. Phoenix application ownership is no
longer pending.
Keep general metrics payload-free and bounded, call inspection tenant-scoped, and full
VM introspection restricted to platform operators. Inspection adds no recording or replay.

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

- **Definition-driven one-agent call**: G1/G2; R10, R47; completed Jido-backed baseline whose behavior the intermediate runtime preserves.
- **Observable sample call**: user-requested operational visibility; existing architecture telemetry goals, failure evidence and embedded reporter independence.
- **Local Morse-code audio providers**: optional local verification capabilities requested during planning.
- **Call Variables and private tool projections**: G3/G5; R17, R18.
- **Conversation during background tools**: G4; R14–R16, R29.
- **Tenant definitions and API-key administration**: G2/G10; R01–R04, R39.
- **Prepared calls and single-use joining**: G2/G10; R05–R10, R39, R40.
- **Asynchronous call history and variable snapshots**: G5/G11; R18, R41.
- **Call inspection and debugging**: user-requested read-only operator workflow over G3/G5/G11; R17, R18, R38, R41; safe live/persisted distinctions.
- **MCP client integration and conformance**: ExMCP public client, thin policy boundary and independent reference validation; R22, R23, R26, R49.
- **ReqLLM agent runtime**: internal inference boundary, exact data-backed tool projection, repeated rounds, streaming/cancellation and migration parity.
- **Remote MCP tools in a live call**: G4/G6; R14–R16, R22–R26, R49; connect pinned remote bindings through the ReqLLM runtime executor.
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

Each of the original 21 milestones was dispatched to a review agent after its draft was created. Reviews
checked vertical outcomes, approved-source fidelity, missing acceptance/failure cases and
index/dependency order. Material findings were corrected and re-reviewed. Those 21 reviews
are complete; review approval is separate from the unchecked implementation boxes.
The released-package investigation subsequently corrected the dependency/binding
boundaries below. Historical agent approvals do not imply they reviewed later edits.
The two new observability specifications received local design/dependency review, recorded
in their own review sections; no independent-agent or implementation verification is implied.

| Milestone | Review status | Evidence |
| --- | --- | --- |
| [Definition-driven one-agent call](definition-driven-call.md#specification-review) | Reviewed; subset clarified | Prior agent review approved AgentServer readiness/teardown boundaries. Released-package probe verified repeated rounds and exposed alias loss; initial static keys must match Action names until the public binding extension exists. |
| [Observable sample call](observable-sample-call.md#specification-review) | Complete; locally reviewed | Phoenix Console, mounted reusable gateway, bounded payload-free telemetry, live diagnostics, deterministic success/failure evidence, embedded-host event contract and Console-owned release assets are implemented and verified. |
| [Local Morse-code audio providers](morse-code-audio-providers.md#specification-review) | Complete; independently reviewed | Real audio, independent fixtures, bounded streaming, explicit transport limits, closed selection, direct-PCM room round trip and optional credential-free sample profile are implemented and verified. |
| [Call Variables and private tool projections](call-variables-and-tool-visibility.md#specification-review) | Approved | Original behavior approved by milestone_review_b; focused Jido review added finite Action-module, strict-envelope and private-context gates. |
| [Conversation during background tools](background-tool-conversation.md#specification-review) | Complete; independently reviewed | Activation-owned bounded workers, serialized private completion continuations, provider interoperability, room projection, operational telemetry and the runnable sample are implemented and verified. |
| [Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md#specification-review) | Complete; independently reviewed | Database-neutral Calls workflows, Ecto/PostgreSQL adapters, immutable publication routes, hash-only scoped keys, restart checks, and trusted operator commands are implemented and verified. |
| [Prepared calls and single-use joining](prepared-call-admission.md#specification-review) | Approved | milestone_review_b; Added pinned join mapping, occurrence timestamps, pre/post-admission token semantics, credential/Origin separation and nonblocking lifecycle handoff; re-review approved. |
| [Asynchronous call history and variable snapshots](asynchronous-call-history.md#specification-review) | Approved | milestone_review_c; Added subscriber crash/saturation isolation, rejected/stale baseline snapshot cases and honest draining; re-review approved. |
| [Call inspection and debugging](call-inspection-and-debugging.md#specification-review) | Complete; locally reviewed | Calls-owned bounded persisted/live projections and the Console-owned authenticated list/detail workflow are implemented and browser-verified. Storage outage, tool failure, authorization, disclosure, archive-gap, lifecycle and reconnection checks pass with the common implementation gates. |
| [MCP client integration and conformance](mcp-client-library.md#specification-review) | Complete; independently reviewed | The maintained ExMCP fork, protocol/policy boundary, official/reference interoperability, security limits and operational visibility are implemented and verified without model exposure. |
| [ReqLLM agent runtime](reqllm-agent-runtime.md#specification-review) | Complete; locally reviewed | The standalone package, exact submit-only loop, activation migration, default-blocking/explicit-non-blocking policy, Jido removal, deterministic failure/lifecycle matrix, responsive rendered call, full umbrella suite and tagged Gemini lane are implemented and verified. |
| [Remote MCP tools in a live call](remote-mcp-tools.md#specification-review) | Revised; partially implemented | Its protocol, configuration, catalog and activation-binding foundations exist. Final model exposure now depends on the ReqLLM agent-runtime milestone instead of a missing Jido extension. |
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
| [Embedded and JSON-configured container delivery](embedded-and-container-delivery.md#specification-review) | Approved; boundary follow-up reviewed | milestone_review_a approved the initial draft; subsequent local review covers gateway-only embedding, optional listener, console-hosted composition and built React assets without changing order. |

## Planning verification

Earlier planning verification on 2026-09-08 (before the released-package follow-up):

- All 21 milestone files have specifications, prerequisites, implementation task lists,
  acceptance/failure checks and manual verification steps. Earlier behavior contracts have
  independent review evidence; focused follow-up review is complete for all five Jido-updated
  specifications. Review approval did not erase the explicit MCP implementation blocker.
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
  dependency findings in that baseline. The focused Jido source/API review corrected the
  production runtime boundary, late-completion handoff and dynamic-tool assumptions.
- The original Jido selection changed implementation mechanisms, not the approved MCP
  profile, count, filenames or order. The public proxy mechanism failed the tenant-catalog
  identity/lifetime gate; direct Jido MCP selection is now superseded by ExMCP.

The released-package follow-up resolved/compiled Jido AI 2.3.0, Jido Action 2.3.2,
ReqLLM 1.22.0 and ExMCP 1.3.0 together in an isolated probe: five deterministic checks
passed, proving repeated Jido rounds and documenting rejected data tools/alias loss.
It retained all 21 milestones and existing protocol/security contracts while separating
standalone ExMCP verification from the live-MCP Jido interface gate. See
[the decision](../jido-tool-execution.md) and [research log](../../labnotes/20260908-1344-jido-ai-evaluation.md).

The subsequent observability update adds two user-requested slices, bringing the current
index to 23. The early dashboard follows the definition-driven call; per-call inspection
follows asynchronous history. Existing filenames, relative ordering and call-definition
contracts are preserved. The new specifications include automated/manual failure checks
and rendered-browser gates. The later approved gateway/console split assigns Phoenix to
the separate console, retaining gateway reuse; dashboard/authentication implementation
choices remain explicit. The affected specifications record a focused ownership/dependency
review; all 23 entries retained their order and implementation status. See the
[observability planning log](../../labnotes/20260908-1725-observability-milestone-plan.md)
and [gateway/console decision](../gateway-console-boundary.md).

The 2026-09-10 runtime decision adds one intermediate slice, bringing the index to 24.
It preserves the completed Jido-backed evidence but selects a separate internal ReqLLM
runtime for forward work, avoiding a Jido fork or missing extension dependency. The new
milestone precedes live MCP, which retains its completed enabling checkboxes and now consumes
the runtime's private executor boundary. Planning inspected ReqLLM 1.22.0 and Legion 0.5.0;
no runtime, provider, dependency-removal, or browser evidence is claimed. See the
[runtime decision](../reqllm-agent-runtime.md) and
[planning labnote](../../labnotes/20260910-0934-reqllm-agent-runtime.md).

This checkpoint changes repository documentation only. No application integration,
browser, live provider, official conformance or umbrella suite execution is claimed;
those remain implementation gates.
The compaction execution/model choice and explicitly identified provider/encoding
particulars still require selection at implementation time.
