# Provider expansion and live acceptance

Status: In progress. Authorized 2026-09-30. Gemini, repaired Deepgram speech,
repaired OpenAI hosted speech, DeepSeek, OpenRouter and Fireworks have selected
passing live evidence. Scoped service/UI acceptance for speech additions,
ElevenLabs and Cartesia implementation, and repository completion gates remain.

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
- [ ] Add reviewed Cartesia and ElevenLabs test models and credentials.
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

- [ ] Implement Cartesia STT and TTS through owned semantic speech sessions.
- [ ] Implement ElevenLabs STT and TTS through owned semantic speech sessions.
- [ ] Implement ElevenLabs agent STS only after confirming its room/tool/history contract.
- [ ] Verify audio negotiation, transcripts, interruption, cancellation, startup
  failure, supervision, usage identity and secret redaction locally.
- [ ] Exercise compiled room support and relevant shared conformance checks.
- [ ] Run bounded selected live tests for each new speech capability.

## Checkpoint E — Platform and tenant Console

- [x] Add direct LLM services to installed setup and call authoring catalogs.
- [x] Prove direct LLM platform/tenant saves, override precedence and request
  privacy at the owning frontend/backend boundaries.
- [x] Verify demo readiness and publication for direct model providers.
- [x] Inspect direct LLM platform/tenant forms at desktop and narrow widths with
  `agent-browser`; local frontend tests cover saved/error states.
- [ ] Repeat scoped save, catalog, publication and rendered acceptance for the
  new speech providers after their capabilities are implemented.

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
The corrected file passes 23 tests; a same-seed root rerun is pending. Cartesia's
reviewed contracts are design progress; neither new speech provider is registered
or advertised as implemented.
