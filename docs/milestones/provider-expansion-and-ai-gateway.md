# Provider expansion and live acceptance

Status: In progress. Authorized 2026-09-30. Gemini, repaired Deepgram speech,
repaired OpenAI hosted speech, DeepSeek, OpenRouter, Fireworks, Cartesia STT/TTS
and ElevenLabs TTS have selected passing live evidence. Both speech providers
have scoped publication/startup checks and implemented-capability Console metadata.
ElevenLabs realtime STT, shared room acceptance and final milestone gates remain.
ElevenLabs hosted-agent STS is deferred by the user-approved 2026-10-01 scope change.

Prerequisites: [Provider integration packages](provider-integration-packages.md),
[Rime and Google speech providers](rime-and-google-speech-providers.md),
[Tenant provider credentials](tenant-provider-credentials-and-platform-configuration.md).
Design sources: [Platform and tenant services](../platform-and-tenant-services.md),
[Provider packages](../provider-integration-packages.md),
[Speech provider comparison](../speech-provider-comparison.md),
[Cartesia and ElevenLabs contracts](../speech-provider-expansion.md), and
[Live provider tests](../live-provider-tests.md).
The [ElevenLabs input turn proposal](../elevenlabs-turn-ownership.md) records
boundary ownership and unresolved design gates; it is not an implemented milestone.
The [remote agent ownership checkpoint](../elevenlabs-agent-ownership.md) separates
historical local monitored cleanup from deferred hosted-agent room integration.
Its unresolved hosted-agent gates are outside the current STT/TTS milestone scope.

## Runnable outcome

Operators and tenants configure direct AI services through the encrypted service
workflow. Published call specs use DeepSeek, OpenRouter and Fireworks for LLM
inference, Cartesia for STT/TTS, and ElevenLabs for realtime STT and TTS.
Explicitly selected live tests exercise configured credentials
without adding billable calls to ordinary `mix test`.

## Approved scope changes

On 2026-09-30 the user clarified that AI gateways are a separate concern from
upstream providers. Cloudflare integration is deferred. Vercel and other gateways
must fit the same independently designed routing concept. The unfinished
Cloudflare provider implementation and tests were removed. Exploration belongs
to [AI gateway routing](ai-gateway-routing.md); it is not an acceptance gate here.
The updated goal adds ElevenLabs and Cartesia speech integrations. These remain
unchecked until their supported contracts and live evidence exist.
Telnyx/Twilio live acceptance remains a separate credentials/destination batch.

On 2026-10-01 the user limited ElevenLabs to realtime STT and TTS because hosted
ElevenAgents has not established a fit for the existing Gemini/OpenAI STS
contracts. The shared STS contracts remain authoritative. Hosted-agent STS is
deferred; it is not an acceptance gate here. Newly written uncommitted agent
definition/tool-resource implementation and tests were removed. Previously
committed protocol/ownership preparation remains historical evidence, with no
STS capability advertised and no further hosted-agent paid checks required.

## Design review

- [x] Preserve tenant override and platform fallback; invalid overrides fail closed.
- [x] Keep generic LLM inference in ReqLLM and credentials/probes in provider packages.
- [x] Keep gateways separate from provider/model identity; defer implementation.
- [x] Review Cartesia session, interruption, transcript and audio contracts.
- [x] Review ElevenLabs phrase TTS request, credit, PCM, cancellation and usage contracts.
- [x] Review Scribe Realtime native VAD separately from its missing speech-start event;
  keep optional agent-output drain outside caller STT prerequisites.
- [x] Review and record the user-approved STT/TTS-only ElevenLabs scope; defer hosted-agent STS.
- [ ] Resolve ElevenLabs realtime STT turn authority without weakening shared contracts.
- [ ] Establish scoped credentials, startup/cancellation, usage and supervision
  contracts for both speech providers before implementation.

## Checkpoint A — Existing live providers

- [x] Verify Mix PubSub works after the access change.
- [x] Gemini tool-schema, transfer-schema and cancellation: 3 passing live tests.
- [x] Deepgram existing five live tests; repair two Gateway turn-completion failures.
- [x] OpenAI hosted reseed/mute/talkover and delegated-tool continuation pass individually.
- [x] Add and pass bounded OpenAI LLM tool/continuation coverage.
- [x] Record existing/direct LLM model/request bounds and sanitized live evidence.

## Checkpoint B — Shared test configuration

- [x] Add a test-owned catalog of fixed current model selections.
- [x] Select current DeepSeek Flash, Gemini Flash Lite through OpenRouter, and
  inexpensive serverless Fireworks Nemotron (listed Gemma models require deployment).
- [x] Extend runner isolation and placeholder template for the direct LLM providers.
- [x] Isolate Cartesia/ElevenLabs keys and add template placeholders.
- [x] Add reviewed Cartesia TTS model/voice selection and its bounded live case.
- [x] Add Cartesia STT selection and its bounded live case.
- [x] Add ElevenLabs TTS Flash 2.5/George selection and one bounded live case.
- [x] Prepare fixed Scribe v2 realtime configuration and one bounded transcription
  protocol case; this does not establish conversational STT acceptance.
- [ ] Complete ElevenLabs conversational realtime STT live cases after contract review.
- [x] Verify runner isolation, argument forwarding and default test exclusion.
- [x] Keep the private env file unchanged; load credentials only with the runner.

## Checkpoint C — Direct LLM services

- [x] Add DeepSeek/OpenRouter/Fireworks manifests and exact single-key schemas.
- [x] Add read-only DeepSeek/OpenRouter credential probes. Fireworks has no
  verified authentication-only probe; its bounded live inference proves credentials.
- [x] Validate public model selection through ReqLLM without exposing transport hooks.
- [x] Prove persisted tenant/platform resolution, Call Spec publication and startup.
- [x] Bounded live tool call, continuation and usage pass individually for all three.

## Checkpoint D — Speech services

- [x] Implement Cartesia TTS through an owned credited request session.
- [x] Implement Cartesia STT through an owned semantic speech session.
- [x] Implement ElevenLabs phrase TTS through an owned credited request session.
- [x] Prepare provider-owned Scribe codec/socket with private authentication,
  bounded PCM framing, explicit segment commits and sanitized typed events.
- [ ] Implement ElevenLabs STT after approving authoritative speech-start/turn-end ownership.
- [x] Prepare closed Scribe VAD query/acknowledgement handling with focused offline tests.
- [x] Fix native VAD probe thresholds explicitly and reject conflicting optional echoes locally.
- [x] Pass the separately selected short Scribe VAD case without a manual commit.
- [ ] Resolve long-input endpoint identity and semantics.
- [ ] Verify audio negotiation, transcripts, interruption, cancellation, startup
  failure, supervision, usage identity and secret redaction locally.
- [ ] Exercise compiled room support and relevant shared conformance checks.
- [x] Pass one bounded selected Cartesia TTS live test.
- [x] Pass one bounded selected Cartesia STT live test.
- [x] Pass one bounded selected ElevenLabs TTS live test.
- [ ] Run selected ElevenLabs conversational realtime STT live tests.

## Checkpoint E — Platform and tenant Console

- [x] Add direct LLM services to installed setup and call authoring catalogs.
- [x] Prove direct LLM platform/tenant saves, override precedence and request
  privacy at the owning frontend/backend boundaries.
- [x] Verify demo readiness and publication for direct model providers.
- [x] Inspect direct LLM platform/tenant forms at desktop and narrow widths with
  `agent-browser`; local frontend tests cover saved/error states.
- [x] Verify Cartesia TTS scoped save, capability catalog, persisted publication,
  compiled startup and rendered platform/tenant forms at desktop/narrow widths.
- [x] Extend Cartesia persisted publication/startup and Console metadata to STT.
- [x] Verify ElevenLabs TTS single-key saves, registered capability metadata,
  encrypted publication, compiled credited startup and tenant/platform precedence locally.
- [x] Inspect ElevenLabs TTS platform/tenant blank-key forms at desktop/narrow widths;
  independent rendered review returns `ship` for these four captured states.
- [x] Complete all five root gates and Lean acceptance for the ElevenLabs TTS checkpoint.
- [ ] Extend ElevenLabs scoped acceptance to realtime STT.

## Checkpoint F — Acceptance

- [ ] Pass relevant local suites and all five root completion gates.
- [ ] Pass Lean verification for speech/state-machine changes.
- [ ] Record selected live evidence; never run all providers together.
- [ ] Synchronize milestone/index, models, docs and labnotes with actual evidence.
- [ ] Commit coherent checkpoints with detailed bodies and push the authorized branch.

## Evidence

Entries below record dated checkpoints. Their earlier STS requirements reflect
the scope before the 2026-10-01 change; hosted-agent work is now deferred. The
current acceptance checklist above requires ElevenLabs realtime STT and TTS only.

See [checkpoint labnotes](../../labnotes/20260930-0353-provider-expansion-gateway.md)
for failures, repairs and selected live results. Passing provider calls do not
establish complete room/UI acceptance. The speech additions and final gates are
still pending; this milestone is not complete.

The [TTS ordering checkpoint](../../labnotes/20260930-0554-tts-completion-order.md)
records a deterministic runtime repair and 318 passing speech/opening-audio
checks. The later full run passed all 520 Gateway tests and exposed an STT fixture
which mistook a denied allocation's unread start notification for its replacement.
The corrected file passes 23 tests; its same-seed root rerun passes all 1683
CallEngine tests. The root run reports 2885 tests across the umbrella and has one
remaining Gateway failure: `after_speech_adoption` preparation times out waiting
for a new progress notification. Its same-seed focused rerun passes one test in
161.3 seconds; its cause is not established and no handoff repair is claimed.
Format, compilation
with warnings as errors, strict Credo and unused-dependency checks pass; the TTS
checkpoint's Lean build/oracle/replay also passes. These are current-checkpoint
results, not final acceptance of the pending speech additions.

The [Cartesia request TTS checkpoint](../../labnotes/20260930-0705-cartesia-request-tts.md)
registers only its implemented TTS capability and exact API-key schema. It shares
Google's extracted request lifecycle without sharing vendor wire parsing. Local
configuration/session/PCM/HTTP, compiled credited usage and persisted scope checks
pass. The selected live request passes one short Sonic 3.6/Skylar phrase.
Console frontend tests pass 208 checks and its independent rendered review says `ship`
for the four captured blank-key form states. Loading/error/inheritance states
have local tests but are not claimed as rendered acceptance. Cartesia STT and
ElevenLabs remain unimplemented; the milestone and index stay unchecked.

The Cartesia TTS root run passes all 2,902 reported tests with zero failures,
72 excluded, seed 412687, including all 1,698 CallEngine and 520 Gateway tests.
All five root completion gates and the Lean lane pass for this checkpoint;
its seven local HTTP checks pass in their explicit integration lane. The earlier
handoff failure is not reproduced, and its cause is still unproven. These gates
accept the TTS checkpoint, not the later STT checkpoint or pending ElevenLabs work.

The [Cartesia STT checkpoint](../../labnotes/20260930-0753-cartesia-turn-stt.md)
implements Ink 2 automatic turns with cumulative text, eager/resume semantics,
allocation-owned sockets and bounded close-and-drain. Its selected live test
passes one connection with a reused public sample. Local compiled session and
persisted scope checks pass; frontend passes 209 checks. Root gates for this
checkpoint are recorded as they finish. Rendered review returns `ship` for the
four captured blank-key platform/tenant states. No final milestone acceptance
or ElevenLabs support is claimed.

The STT checkpoint's initial seed-149103 root run reports one Telnyx
custom-URL/destination-loss recovery-speech failure. Its selected-case and
thirteen-test whole-file reruns pass. The subsequent full same-seed rerun
passes all 2,922 reported tests, zero failures and 74 exclusions, including
1,718 CallEngine, 520 Gateway and 193 Console checks. All five root gates
and Lean pass for this checkpoint. The intermittent failure's cause remains
unproven; a separate focused fixture-ordering investigation is open.
ElevenLabs and final shared milestone acceptance remain pending.

A subsequent Gateway fixture checkpoint supplies valid credited acknowledgement
PCM before recovery, checks replacement readiness without requiring a duplicate
progress notification, and establishes RTVI readiness before room-end departure.
The [phone recovery](../../labnotes/20260930-0851-phone-recovery-order.md),
[handoff progress](../../labnotes/20260930-0924-handoff-progress-order.md), and
[departure readiness](../../labnotes/20260930-0945-rtvi-departure-readiness.md)
labnotes distinguish deterministic boundary violations from inferred intermittent
ordering. Two new owned recovery checks and the selected handoff/RTVI checks pass.
All five root completion gates pass; the same-seed full run reports 2,924 tests,
zero failures and 74 exclusions, including all 522 Gateway tests. Production
protocols, timeouts and state machines are unchanged. The milestone remains
in progress while ElevenLabs and final shared acceptance are pending.

The [ElevenLabs request TTS checkpoint](../../labnotes/20260930-0911-elevenlabs-request-tts.md)
adds only its implemented TTS capability and a single private API-key schema.
Vendor HTTP/configuration/PCM handling stays in its provider directory; the
shared owned request session supplies credit, cancellation and measured usage.
Compiled session, registry, loopback HTTP and encrypted platform/tenant
publication checks pass. One selected Flash 2.5/George/16 kHz live request passes
with no retry. Frontend tests pass 216 checks with TypeScript and lint clean.
Independent rendered review returns `ship` for the four blank-key forms. The
root run passes all 2,931 reported tests with zero failures and 82 exclusions,
seed 149103, including 1,724 CallEngine, 522 Gateway and 194 Console checks.
All five root completion gates and Lean pass for this checkpoint. Seven local
HTTP checks also pass after replacing a swallowed callback assertion with
explicit unexpected-PCM observation. STT and agent STS remain unimplemented
and are not advertised by the Console catalog; the milestone/index remain open.

The [Scribe protocol checkpoint](../../labnotes/20260930-1042-elevenlabs-turn-contracts.md)
prepares a closed codec and allocation-ready supervised wire worker. Seven local
configuration/framing/privacy checks pass. One selected live connection returns
the sample's known final word after 5.16 seconds of input. Two earlier connections
failed acknowledgement validation before sending audio; the verified optional
acknowledgement fields are now accepted while conflicting values fail closed.
The final privacy delivery refactor is checked locally without repeating the
passing provider call. These results establish protocol preparation only;
ElevenLabs conversational STT/agent STS and final milestone acceptance remain open.

All five root gates pass for the protocol checkpoint. The seed-149103 default run
reports 2,936 tests, zero failures and 85 exclusions, including 1,729 CallEngine,
522 Gateway and 194 Console checks. Its protocol code changes no speech state
machine or source cutover; Lean is not repeated for this checkpoint. The new
[input turn proposal](../elevenlabs-turn-ownership.md) separates design review
from implementation and leaves detector feasibility and final-segment completion
gates unchecked. The milestone and index remain in progress.

The [hosted-agent protocol checkpoint](../../labnotes/20260930-1120-elevenlabs-agent-protocol.md)
prepares provider-owned native framing, supervised socket transport, private
signed connections and a bounded provisioning probe which explicitly checks
deletion of each created agent. Twenty-four local checks pass, including one
loopback transport case. Controlled metadata checks distinguish rejected hosted
Flash 2.5 configuration from accepted V4 Turbo; saved configuration confirms
the enabled completion event. One selected Gemini 3.5 Flash Lite/V4 Turbo/George
conversation recognizes the public sample, returns bounded PCM and emits a
matching whole-response completion event. Earlier creation, ping and completion
failures remain documented. This is protocol preparation, not room/tool/history,
runtime resource ownership, scoped STS or conversational STT acceptance.

All five root gates pass for this hosted protocol checkpoint. Its seed-149103
default run reports 2,959 tests, zero failures and 89 exclusions, including
1,752 CallEngine, 522 Gateway and 194 Console checks. No speech/source state
machine changes require another Lean run for this preparation; the eventual
runtime STS integration still requires its own room, browser and Lean gates.
The milestone/index remain unchecked.

The [agent ownership checkpoint](../../labnotes/20260930-1321-elevenlabs-agent-ownership.md)
adds a named application-owned resource supervisor ahead of room supervision.
Temporary controllers stay responsive while separate workers run bounded HTTP
preparation/deletion. Monitors retain cleanup across owner or controller death;
graceful shutdown waits for the explicit deletion result. Thirty-seven combined
local protocol/API/socket/ownership/application checks pass, including the real
API helper against a synthetic HTTP Plug. No paid case is repeated, no STS
manifest entry is added, and no room support is claimed. Durable request-worker/
VM-loss reconciliation and full conversational STT/STS acceptance remain open.
All five root gates pass: format, warnings compile, strict Credo, default test
and unused dependencies. The default suite reports 2,968 tests, zero failures,
89 exclusions, seed 149103 (CallEngine 1,761; Gateway 522; Console 194).

The [input turn feasibility review](../elevenlabs-turn-ownership.md#feasibility-review-2026-09-30)
is recorded separately from implementation acceptance. Teammate research and two
review/fix passes confirm that SDK segment-buffer clearing does not establish
completion across automatic/manual races or empty remainders. Recognized-word
timestamps cannot establish processed-through audio. Detector runtime versions,
threading uncertainty and a concrete offline probe are documented; no model,
dependency or experiment is installed by this research. Speech Engine's public
callback protocol is an unimplemented alternative requiring further design.
Standalone conversational STT remains required and unchecked. Hosted room STS,
which was required when this review was recorded, is now deferred.

The [tool-resource investigation](../../labnotes/20260930-2305-elevenlabs-tool-resources.md)
previously passed 49 combined local checks and one selected 4.4-second live
metadata case, seed 103331. Failed cleanup attempts were recovered and a provider
read confirmed no matching test residues. This is historical investigation
rather than current implementation acceptance: its uncommitted tool API, lease
extension and tests were removed following the STT/TTS-only scope decision.
Previously committed agent protocol/ownership code remains unchanged. The
[agent-definition investigation](../../labnotes/20260930-2351-elevenlabs-agent-definition.md)
also records the withdrawn per-call configuration work and its unresolved tests.
Neither investigation advertises an STS capability or completes a current gate.

The [native VAD preparation](../../labnotes/20260930-2340-elevenlabs-native-vad.md)
adds validated Scribe manual/VAD protocol modes and request-specific
acknowledgement handling. Four new focused checks first fail, then all nine
offline checks pass on current sources, seed 980595. The separate bounded VAD
live case is written but unrun; no billable request is made for this preparation.
Format and documentation checks pass. Before the access change, Mix compilation,
strict Credo, test startup and dependency locking were denied TCP access; earlier tool-only
gate results did not verify this later source change. Git metadata was declared
read-only, so the checkpoint could not then be staged, committed or pushed.
Native VAD evidence is assessed before any local detector selection, while
genuine onset and long-input endpoint contracts still need resolution.

The [fixed native-boundary checkpoint](../../labnotes/20261001-0016-scribe-native-boundaries.md)
requests explicit native VAD settings and rejects conflicting optional echoes.
The focused lane first reports ten checks with two expected failures, then passes
ten checks. These results improve reproducibility of the unrun selected probe;
they do not establish native speech-start, long-input endpointing or room admission.
At that checkpoint, shell DNS prevented obtaining detector/runtime artifacts for the separate
local activity feasibility probe. No detector dependency is added, no live case
was repeated and the milestone remained unchecked. The then-current root Mix gates
failed before project execution at TCP startup/locking (`:eperm`).

The [native VAD acceptance checkpoint](../../labnotes/20261001-0037-scribe-vad-acceptance.md)
confirms restored Mix TCP/DNS access and passes the selected native VAD case:
one test, zero failures, one excluded, 6.6 seconds, seed 205077. The initial
attempt fails at PostgreSQL authentication before provider contact; using the
local Unix socket resolves it. Twelve owning codec/socket checks pass, including
loopback transport. No manual, TTS, hosted-agent or other paid provider case is
repeated. Genuine speech-start, long-input turn identity and integrated realtime
STT acceptance remain open. Earlier sandbox-blocked entries above are historical;
the final restored-access root test result is recorded with this checkpoint.

All five root gates pass for native VAD preparation and the approved scope update.
The default umbrella run completes with 2,973 reported tests, zero failures,
90 exclusions, seed 899045 (CallEngine 1,766; Gateway 522; Console 194).
No source-cutover or speech state machine changes require a new Lean run for this
checkpoint. This evidence supersedes earlier execution restrictions for this
code, while conversational realtime STT and final milestone acceptance remain open.
