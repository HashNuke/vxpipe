# Provider expansion and live acceptance

Status: In progress. Authorized 2026-09-30. Gemini, repaired Deepgram speech,
repaired OpenAI hosted speech, DeepSeek, OpenRouter, Fireworks and Cartesia STT/TTS
have selected passing live evidence. Cartesia has scoped publication/startup
checks and Console metadata. ElevenLabs, shared room acceptance and the final
repository completion gates remain.

Prerequisites: [Provider integration packages](provider-integration-packages.md),
[Rime and Google speech providers](rime-and-google-speech-providers.md),
[Tenant provider credentials](tenant-provider-credentials-and-platform-configuration.md),
and [Agent speech-to-speech](agent-speech-to-speech.md) for hosted agent STS.
Design sources: [Platform and tenant services](../platform-and-tenant-services.md),
[Provider packages](../provider-integration-packages.md),
[Speech provider comparison](../speech-provider-comparison.md),
[Cartesia and ElevenLabs contracts](../speech-provider-expansion.md), and
[Live provider tests](../live-provider-tests.md).

## Runnable outcome

Operators and tenants configure direct AI services through the encrypted service
workflow. Published call specs use DeepSeek, OpenRouter and Fireworks for LLM
inference, Cartesia for STT/TTS, and ElevenLabs for STT/TTS and the verified
agent STS contract. Explicitly selected live tests exercise configured credentials
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

## Design review

- [x] Preserve tenant override and platform fallback; invalid overrides fail closed.
- [x] Keep generic LLM inference in ReqLLM and credentials/probes in provider packages.
- [x] Keep gateways separate from provider/model identity; defer implementation.
- [x] Review Cartesia session, interruption, transcript and audio contracts.
- [ ] Review ElevenLabs STT/TTS and agent STS separately from voice conversion.
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
- [ ] Add ElevenLabs selections and live cases.
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
- [ ] Implement ElevenLabs STT and TTS through owned semantic speech sessions.
- [ ] Implement ElevenLabs agent STS only after confirming its room/tool/history contract.
- [ ] Verify audio negotiation, transcripts, interruption, cancellation, startup
  failure, supervision, usage identity and secret redaction locally.
- [ ] Exercise compiled room support and relevant shared conformance checks.
- [x] Pass one bounded selected Cartesia TTS live test.
- [x] Pass one bounded selected Cartesia STT live test.
- [ ] Run selected ElevenLabs speech live tests.

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
- [ ] Repeat scoped acceptance for ElevenLabs.

## Checkpoint F — Acceptance

- [ ] Pass relevant local suites and all five root completion gates.
- [ ] Pass Lean verification for speech/state-machine changes.
- [ ] Record selected live evidence; never run all providers together.
- [ ] Synchronize milestone/index, models, docs and labnotes with actual evidence.
- [ ] Commit coherent checkpoints with detailed bodies and push the authorized branch.

## Evidence

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
