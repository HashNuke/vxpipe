# Call-definition implementation milestones

Status: 23 milestone specifications; milestone 1 is complete and milestone 2 is next. The earlier
behavior contracts have completed focused review. The 2026-09-08 released-package investigation
updated the Jido/ExMCP boundaries; the live-MCP slice retains one explicit public
runtime-tool interface blocker. Standalone MCP client work is independent of that gap.
Source baseline: `9eb35a4` (approved design), plus the user-approved Morse and internal
MCP-library additions and Jido runtime selection documented during planning on 2026-09-08.
Jido AI replaces custom agent-loop work; ExMCP supplies the protocol client behind
`vxpipe_mcp`. See the [loop/tool-binding decision](../jido-tool-execution.md).
That integration change stayed inside existing milestones. The subsequent user-requested
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

1. [x] [Definition-driven one-agent call](definition-driven-call.md) — Compile a typed, pinned plan and run its text/audio and host-tool conversation through Jido AI.
2. [ ] [Observable sample call](observable-sample-call.md) — Run a sample conversation and inspect live timing, provider failures and VM health on a separate dashboard.
3. [ ] [Local Morse-code audio providers](morse-code-audio-providers.md) — Exercise real audio ingress/egress with deterministic text-to-tones and tones-to-text providers.
4. [ ] [Call Variables and private tool projections](call-variables-and-tool-visibility.md) — Read/update sectioned variables through tools without exposing private data.
5. [ ] [Conversation during background tools](background-tool-conversation.md) — Keep conversation responsive while a submitted tool finishes.
6. [ ] [Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md) — Save immutable definitions and bootstrap tenant-scoped administrative access.
7. [ ] [Prepared calls and single-use joining](prepared-call-admission.md) — Prepare in PostgreSQL, then start exactly one live call when its caller joins.
8. [ ] [Asynchronous call history and variable snapshots](asynchronous-call-history.md) — Archive permitted events without putting PostgreSQL in the live-call critical path.
9. [ ] [Call inspection and debugging](call-inspection-and-debugging.md) — Inspect an authorized live or ended call's timeline, permitted snapshots, timings and archival gaps.
10. [ ] [MCP client integration and conformance](mcp-client-library.md) — Verify ExMCP through a thin policy adapter and version-pinned reference/conformance server, independently of Jido.
11. [ ] [Remote MCP tools in a live call](remote-mcp-tools.md) — Run a validated, tenant-configured remote tool while talking.
12. [ ] [Opening audio and call lifecycle](opening-audio-and-call-lifecycle.md) — Play optional opening audio, greet, and enforce approved live-call timers.
13. [ ] [Allowlisted agent-to-agent transfers](agent-transfers.md) — Transfer responsibility between agent participants without losing variables.
14. [ ] [Live mixing and presence-driven media policy](live-mixing-and-media-policy.md) — Route/mix multiple participants live and enforce transcript/audio denials.
15. [ ] [Private briefing and human web acceptance](human-web-transfers.md) — Privately brief a destination, accept over web control, then bridge human-only audio.
16. [ ] [Telnyx calls and phone transfers](telnyx-calls.md) — Connect verified telephony legs through the same admission and transfer contracts.
17. [ ] [Twilio through the common telephony contract](twilio-calls.md) — Prove a second provider fits without changing participant definitions or room control.
18. [ ] [Permitted live recordings streamed to S3](streaming-recordings.md) — Record live mix and separate tracks without blocking participants or saving denied intervals.
19. [ ] [Usage, cost observations, and billing enrichment](usage-and-billing-observations.md) — Inspect honest call/participant/turn usage even when prices are unavailable.
20. [ ] [Versioned call-details publications](call-details-publications.md) — Publish immutable timestamp-named details and honest completion state after calls end.
21. [ ] [Whole-call retention and deletion](call-retention.md) — Sweep expired calls, deleting external artifacts before database records.
22. [ ] [Context compaction and supported LLM fallback](context-compaction-and-native-fallback.md) — Continue long conversations within model limits without changing tool or privacy authority.
23. [ ] [Embedded and JSON-configured container delivery](embedded-and-container-delivery.md) — Run the same platform through host application settings or a standalone JSON-configured image.

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
Use one `Jido.AI.Agent`/AgentServer as the supervised inference child of each active agent
participant, replacing the current custom model/tool-loop process rather than becoming a
competing participant authority. Jido owns that agent's ReAct requests, conversation
projection and registered Jido Actions; ReqLLM remains its provider layer. Vxpipe still owns
identities, turn serialization, authorization, stream/TTS projection, interruption,
submitted background workers, transfers, variables and room lifecycle. Standalone ReAct is
limited to focused adapter tests, not a parallel production loop.
Introduce `vxpipe_calls` for application workflows, `vxpipe_persistence` for Ecto/Repo,
and `vxpipe_artifacts` for object storage only in their owning milestones. The gateway
authenticates/translates; it does not gain direct Repo or provider orchestration ownership.
The separate `vxpipe_mcp` internal library depends directly on `ex_mcp`, not Jido AI,
Jido Action, `jido_mcp` or Jido Connect. ExMCP owns protocol/transport lifecycle through
public APIs. The wrapper configures supervision, scoped client reuse, policy enforcement
and result mapping without room, tenant-selection, Repo or gateway dependencies. Its
standalone integration/conformance checkpoint targets MCP `2025-11-25`, replacing the
earlier `2026-07-28` profile. No custom-client fallback.
The engine-side Jido tool bridge is a separate concern. Current Jido AI expects Action
modules, loses map aliases during model projection and lacks the required public data-tool
executor interface. The live-MCP milestone must prove that extension before shipping.
Early static-tool slices accept only keys matching Action names and reject unsupported
aliases; this is an explicit rollout subset, not a change to the final alias contract.
No externally driven atom/module generation, private proxy APIs, generic model-visible
endpoint/tool dispatcher or replacement custom LLM loop is an acceptable workaround.
Preserve dependency direction in child `mix.exs` files.

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
is an alternative embedding mode. React/Vite remains the sample implementation;
moving asset ownership does not mean rewriting the sample in LiveView.
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

- **Definition-driven one-agent call**: G1/G2; R10, R47; supervised per-activation Jido AI/Jido Action agent loop.
- **Observable sample call**: user-requested operational visibility; existing architecture telemetry goals, failure evidence and embedded reporter independence.
- **Local Morse-code audio providers**: optional local verification capabilities requested during planning.
- **Call Variables and private tool projections**: G3/G5; R17, R18.
- **Conversation during background tools**: G4; R14–R16, R29.
- **Tenant definitions and API-key administration**: G2/G10; R01–R04, R39.
- **Prepared calls and single-use joining**: G2/G10; R05–R10, R39, R40.
- **Asynchronous call history and variable snapshots**: G5/G11; R18, R41.
- **Call inspection and debugging**: user-requested read-only operator workflow over G3/G5/G11; R17, R18, R38, R41; safe live/persisted distinctions.
- **MCP client integration and conformance**: ExMCP public client, thin policy boundary and independent reference validation; R22, R23, R26, R49.
- **Remote MCP tools in a live call**: G4/G6; R14–R16, R22–R26, R49; public Jido runtime-tool binding interface gate.
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
| [Observable sample call](observable-sample-call.md#specification-review) | Implementation in progress; locally reviewed | Phoenix Console, mounted reusable gateway, bounded payload-free telemetry, live diagnostics, deterministic failure fixture, embedded-host event contract and Console-owned release assets are implemented with runtime/UI evidence. Final failure checks remain. |
| [Local Morse-code audio providers](morse-code-audio-providers.md#specification-review) | Approved | milestone_review_a; real audio, independent fixtures, bounded streaming and explicit transport limits. |
| [Call Variables and private tool projections](call-variables-and-tool-visibility.md#specification-review) | Approved | Original behavior approved by milestone_review_b; focused Jido review added finite Action-module, strict-envelope and private-context gates. |
| [Conversation during background tools](background-tool-conversation.md#specification-review) | Approved | Original behavior approved by milestone_review_c; focused Jido review added the retained in-memory Vxpipe mailbox/internal-continuation boundary instead of best-effort Jido injection. |
| [Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md#specification-review) | Approved | milestone_review_a; Separated reusable revision metadata from per-call plan/credential resolution; excluded credentials and leases from revisions/routes; focused re-review approved. |
| [Prepared calls and single-use joining](prepared-call-admission.md#specification-review) | Approved | milestone_review_b; Added pinned join mapping, occurrence timestamps, pre/post-admission token semantics, credential/Origin separation and nonblocking lifecycle handoff; re-review approved. |
| [Asynchronous call history and variable snapshots](asynchronous-call-history.md#specification-review) | Approved | milestone_review_c; Added subscriber crash/saturation isolation, rejected/stale baseline snapshot cases and honest draining; re-review approved. |
| [Call inspection and debugging](call-inspection-and-debugging.md#specification-review) | Scope requested; locally reviewed | Authorized live/ended call workflow, tenant isolation, revisions/lag, bounded subscriptions and no audio/privacy bypass; console-owned pages use public Calls/live projections after their prerequisites. |
| [MCP client integration and conformance](mcp-client-library.md#specification-review) | Revised after investigation | ExMCP replaces direct Jido MCP; protocol/policy gates remain. No Jido dependency or model exposure in this standalone slice; transport conformance is not yet demonstrated. |
| [Remote MCP tools in a live call](remote-mcp-tools.md#specification-review) | Revised; implementation blocked | Owns the required public Jido AI data-tool projection/executor gate, exact aliases/schemas and mixed-loop proof; ExMCP alone does not resolve it. |
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
review; all 23 entries retain their order and unchecked implementation status. See the
[observability planning log](../../labnotes/20260908-1725-observability-milestone-plan.md)
and [gateway/console decision](../gateway-console-boundary.md).

This checkpoint changes repository documentation only. No application integration,
browser, live provider, official conformance or umbrella suite execution is claimed;
those remain implementation gates.
The compaction execution/model choice and explicitly identified provider/encoding
particulars still require selection at implementation time.
