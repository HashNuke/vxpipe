# Provider expansion acceptance review

> Relocated from `docs/provider-expansion-acceptance.md` on 2026-10-09. First recorded source commit: `2b24bbeb7630` (2026-10-01T06:21:20+00:00).
> Supporting plan/evidence companion. [provider-expansion-and-ai-gateway](provider-expansion-and-ai-gateway.md) owns current scope, implementation checklists and acceptance; [the index](index.md) owns order. This is not a new independently ordered milestone.
> This is the terminal evidence audit for the approved STT/TTS-only scope. The completed owner retains acceptance authority. Historical evidence checklists do not add requirements for deferred hosted-agent STS, gateway routing or paid carrier interoperability.

Status: accepted under the approved scope, 2026-10-01. The
[implementation milestone](provider-expansion-and-ai-gateway.md)
is complete. This review distinguishes exercised application boundaries from
provider protocol evidence and records the terminal acceptance and its limits.

## Approved requirements and evidence

| Requirement | Evidence inspected | Current conclusion |
| --- | --- | --- |
| Repair selected Gemini, Deepgram and OpenAI live tests | [Existing-provider labnotes](../20260930-0353-provider-expansion-gateway.md), corresponding tagged adapter/runtime/Gateway tests | Selected provider checks pass; silence framing and OpenAI history/Responses repairs are recorded. |
| Add DeepSeek, OpenRouter and Fireworks LLM services | Registry manifests, shared ReqLLM selection and scoped `PlanStartup.AgentModelTest`, persisted `DemoSamplesTest`, `DirectLLMRoomTest`, scoped frontend forms, [direct-service labnotes](../20260930-0638-direct-llm-services.md) | Exact single-key services, private tenant/platform resolution and published model selections are exercised locally. Three actual compiled rooms resolve their selected credential and reach open input with an admitted agent, without billable inference. Individually selected live tool/continuation/usage cases pass. |
| Use fixed economical test models | Test-owned `LiveModels` catalog and bounded live contract; primary-source selections recorded in provider labnotes | Fixed reviewed models and request bounds are shared without additional model environment variables. Fireworks uses a serverless model because listed Gemma models require deployment. |
| Cartesia STT/TTS and ElevenLabs TTS | Provider configuration, wire, semantic-session, private startup and persisted activation tests; selected live cases; rendered form evidence | Provider and scoped-service boundaries pass. Five exact-provider room checks additionally exercise transcript publication/model input, credited playback completion and interruption/replacement. |
| ElevenLabs realtime STT | [Session decision](../../docs/elevenlabs-stt-session.md), local room test, native activity/input tests, [configured-room evidence](../20261001-0505-scribe-configured-room.md) | A published room reaches the real recognizer through an encrypted platform service and production reader. One long acoustic turn preserves intermediate recognition and prefix/suffix text. Earlier short, two-turn and initial-idle session cases remain separate evidence. |
| Turn ownership and long recognition | Fixed local acoustic onset/gap authority, serialized manual segments, fresh per-turn connections, bounded PCM/turn queues | Recognition segments never substitute for acoustic endpoints. STT reports `local_gap`; shared STS authority remains unchanged. |
| Cancellation, credit, failure and supervision | Provider session tests, `RequestTTSSessionTest`, shared `ProviderContractTest`, allocation and room consumer suites | Cartesia and ElevenLabs descriptors now enter the shared contract checks. ElevenLabs TTS additionally enters the shared request credit/cancellation/failure/worker-retirement matrix. |
| Native input admission | [Admission checkpoint](../20261001-0522-scribe-input-admission.md), modeled result-before-worker-retirement regression, ordered PCM/capacity checks | One native job executes; accepted pending PCM remains ordered and bounded. Outcome/admission waits for monitored worker termination. |
| Explicit live lane and private credential loading | All child test exclusions; shell runner isolation/forwarding checks; template; tagged provider cases | Live cases are excluded by default. Deferred hosted-agent probes are explicitly skipped even under provider/live selection. The runner includes Console's configured-service lane and loads credentials only into its child process. The private environment file was neither inspected nor edited. |
| Platform/tenant configuration UI | Registry-driven capability metadata, private key forms, persisted scope checks and rendered desktop/narrow captures in checkpoint notes | Installed capabilities and single-key configuration are verified. Saved/error/inheritance behavior is covered locally; screenshots alone do not prove persistence. |
| Gateway exploration and carrier scope | [Gateway routing design](ai-gateway-routing.md), milestone scope amendments | Cloudflare/Vercel routing is separate from upstream identity. Implementation and carrier live acceptance remain approved deferrals. |
| Final gates, documentation, commits and push | Current root/Lean commands, milestone/index and authorized branch | All five root gates and Lean pass. The final same-seed full rerun reports 3,031 tests, zero failures and 97 exclusions; three added LLM room-startup cases pass separately. Earlier Gateway failure causes remain unproven. Evidence, checklist and authorized checkpoint publication are synchronized. |

## Whole-room evidence

Compiled configuration plus a standalone semantic allocation proves adapter
selection and session compatibility. It does not by itself exercise the whole
room's ingestion, transcript publication, agent speech routing or sink playout.
The additional owning CallEngine checks now pass in
`SpeechExpansionRoomTest`; final umbrella acceptance also passes:

- [x] Cartesia STT receives caller PCM through compiled room ingress and publishes
  the provider's definitive transcript with the room's turn identity.
- [x] Cartesia and ElevenLabs TTS route compiled agent output through credited
  room playback, including completion and interruption boundaries.
- [x] Record final umbrella acceptance on those checks and synchronize the
  milestone/index before claiming completion.

These local cases use synthetic credentials and owned wire/request fixtures.
Previously passing billable provider operations need not be repeated to prove
these application boundaries. Carrier phone interoperability remains a separate
approved batch.

## Decisions and rejected alternatives

Keep protocol, scoped credential and whole-room evidence explicit. Reject
checking off complete room acceptance from provider-only calls or compiled
startup alone. Reuse shared speech and ReqLLM contracts while testing the
project-owned composition boundaries; do not copy vendor integrations into
room modules.

Retain genuine acoustic endpoints for standalone Scribe recognition and bound
queued PCM during native inference. Reject hiding admission failures by adding
initial artificial silence, delaying caller audio, or treating intermediate
recognition commits as final caller turns.

ElevenLabs hosted-agent STS remains deferred under the approved STT/TTS-only
scope. Gateway implementations remain deferred under their separate routing
proposal. Neither becomes an acceptance requirement through historical links.

The [room acceptance checkpoint](../20261001-0544-speech-room-acceptance.md)
records the initial four TTS startup failures and closed trusted-settings repair.
The runtime already supports a private request-module seam; its catalog now
admits that setting while keeping public authoring hooks rejected. Five cases
pass locally. The broad room gate is satisfied by these checks and the separate
configured Scribe live case, rather than by startup-only evidence.

The [Gateway gate investigation](../20261001-0559-gateway-final-acceptance.md)
records the complete-source failures and bounded selected/file reruns. Their
passing outcomes do not establish a repair or the original scheduling causes.

Three direct LLM room-startup cases additionally pass locally, seed 369583, in
3.2 seconds. They select each new upstream explicitly, resolve its scoped
credential through normal startup and attach caller media before asserting open
input and the joined agent. Existing standalone resolution/publication evidence
is supplemented by an actual room boundary. The production ReqLLM adapter is
selected; the wait-for-input agent makes no remote model request.

## Terminal gates and limits

The full same-seed root rerun exits zero: 3,031 tests, zero failures, 97
exclusions, seed 232973, including 1,822 CallEngine, 522 Gateway and 195 Console
checks. Format, warnings-as-errors compilation, strict Credo, unused dependencies
and Lean build/oracle/replay pass. The direct LLM room additions and historical
skip tag were applied after the full run loaded CallEngine tests; their separate
root/focused results supplement that run without changing production source.
Do not report their count as part of the full suite. Final formatting and Credo
include those additions. Earlier Gateway failures remain recorded; a green
rerun does not prove their original scheduling causes.

The admitted provider capabilities, exact credential schemas, scoped startup,
persisted publication, room consumers, selected live protocol/runtime evidence
and rendered configuration meet the approved milestone. The historical hosted
agent probes are skipped; no hosted-agent STS contract is accepted. Separate
gateway routing and paid carrier interoperability retain their approved deferrals.
