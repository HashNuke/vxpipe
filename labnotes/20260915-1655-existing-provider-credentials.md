# Existing provider credential inventory

> Relocated from `docs/existing-provider-credentials.md` on 2026-10-09. First recorded source commit: `0ff30b79e1a0` (2026-09-15T23:55:48+07:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260915-2351-existing-provider-inventory](20260915-2351-existing-provider-inventory.md).
> Maintained contracts/progress: [provider-integration-packages](../docs/provider-integration-packages.md), [provider-credential-storage](../docs/provider-credential-storage.md). Detailed contract refinements are deferred to the separately reviewed documentation work.
> Its removed provider-module links are source evidence at the cited `b5917ae` baseline, not current file locations.

## Scope and evidence

This inventory bounds checkpoint 5 of the [credential milestone](milestones/tenant-provider-credentials-and-platform-configuration.md).
It preserves provider integrations demonstrated by Vxpipe before the tenant-credential cutover.
The reference tree is `b5917ae`, immediately before encrypted provisioning was implemented.
Installed ReqLLM adapters, model catalog entries and website logos do not add requirements.

| Existing integration | Existing authentication | Project-owned evidence | DB migration status |
| --- | --- | --- | --- |
| Google Gemini model inference | API key | [ReqLLM constructor tests](../apps/vxpipe_agent_runtime/test/vxpipe/agent_runtime/provider/req_llm_test.exs), [Google integration lane](../apps/vxpipe_agent_runtime/test/integration/req_llm_provider_test.exs), and the development model selection in `b5917ae:config/dev.exs` | Inline tenant lookup implemented in checkpoints 1–2. |
| Deepgram Flux STT and TTS | API key | [STT adapter](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/provider/deepgram/flux.ex), [TTS adapter](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/provider/deepgram/flux_text_to_speech.ex), and both development selections in the reference tree | Inline tenant lookup implemented in checkpoints 1–2. |
| Zenmux model inference and native routing | API key for Zenmux | [Encoded request test](../apps/vxpipe_agent_runtime/test/vxpipe/agent_runtime/provider/req_llm_native_routing_test.exs), introduced by `e9d3ab4`; pre-cutover Engine activation test described below | Inline selection, named tenant lookup and native routing implemented; checkpoint 5 verification is recorded in the milestone ledger. |
| Telnyx Voice API | API key; webhook verification uses the service's Ed25519 public key | [Existing carrier configuration](../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/telnyx/service_profile.ex), [command tests](../apps/vxpipe_gateway/test/vxpipe/gateway/telephony/telnyx/adapter_test.exs), [verification tests](../apps/vxpipe_gateway/test/vxpipe/gateway/telephony/telnyx/webhook_verifier_test.exs) | Encrypted provisioning, tenant service lookup and live command/webhook readers implemented in checkpoint 3. |
| Twilio Voice | Account SID and Auth Token | [Existing carrier configuration](../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/twilio/service_profile.ex), [command tests](../apps/vxpipe_gateway/test/vxpipe/gateway/telephony/twilio/adapter_test.exs), [webhook and media readers](milestones/tenant-provider-credentials-and-platform-configuration.md#checkpoint-4--move-twilio-credential-readers-to-tenant-storage) | Encrypted provisioning and matching service registration supply live REST, webhook and retained WSS authentication in checkpoint 4. |
| Local Morse speech and test fixtures | None | [Current capability catalog](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability_catalog.ex) and the Morse adapters in the reference tree | Preserve credential-free operation. |

The original carrier milestones own live-provider acceptance. This inventory records source and
test support; it does not claim that an excluded live lane has run or that every migration is done.
Deepgram retains its existing model, encoding and sample-rate options. Telnyx retains connection
identity and public verification metadata; Twilio retains Account SID matching at its command and
signature boundaries. None of these source changes requires a new authentication method.

## Later OpenAI addition

The [GPT-Live speech milestone](milestones/gpt-live-speech-to-speech.md) adds a
direct `openai` provider after this historical inventory. It accepts one tenant
API key through the existing encrypted credential storage and reader, previews
only the last four characters, and validates the key with a model-list request
to `https://api.openai.com/v1/models`. Its manifest advertises credential,
credential-validation and speech-to-speech capabilities. The same saved key
authenticates direct OpenAI language models through ReqLLM.

## Zenmux contract to preserve

The reference tree's
`apps/vxpipe_call_engine/test/vxpipe/call_engine/plan_startup/agent_model_profile_test.exs`
constructs an actual ReqLLM configuration for `zenmux:openai/gpt-5` through Engine activation.
It verifies a nested native routing object and generation options, rejects that routing object
for Google, and rejects executable generation hooks. The old profile mechanism is removed;
its demonstrated model/option behavior must survive the inline replacement.

The Agent Runtime request test observes one request to `/api/v1/chat/completions` with model
`openai/gpt-5`, the native routing object (`fallback`, `routing.type`, `routing.providers` and
`routing.primary_factor`) and the exact tool schema. It retains the provider's
reported model and usage. These are existing behavior, not a new router feature.

Checkpoint 5 supplies the existing Zenmux API-key shape from tenant storage, inline
provider/model translation, the supported nested native routing data and focused request checks.
Public options still cannot replace credentials or redirect credential-bearing requests.
The [current translator](../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/provider_selection.ex)
supports Google, Zenmux and direct OpenAI. See the [inline example](../docs/inline-provider-selections.md#provider-translation)
and [checkpoint evidence](20260916-0033-zenmux-tenant-credentials.md).

The [public room-startup regression](../apps/vxpipe_call_engine/test/vxpipe/call_engine/call_spec_driven_call_test.exs)
also verifies that a Zenmux entry agent passes startup validation and prepares using its named
tenant credential. Follow-up review found a stale Google-only hosted startup allowlist after the
initial constructor checks; the [correction evidence](20260916-0118-zenmux-room-startup.md)
records its expected failure and fix.

`openai` and `anthropic` in these tests identify models or destinations selected by Zenmux.
They do not establish separate OpenAI or Anthropic authentication integrations in Vxpipe.
The caller supplies one Zenmux credential.

## Excluded additions

At the reference commit, the inventory found no separate Vxpipe integration test or configured
reader for direct OpenAI, Anthropic, OpenRouter, Bedrock, Azure or Vertex authentication. The generic internal ReqLLM
constructor can accept catalog models; that alone does not commit this milestone to implementing
tenant authentication for every catalog provider. The later OpenAI addition is
tracked by the GPT-Live milestone; the other names remain outside this scope.

Do not add cloud signing, service-account JSON, OAuth onboarding/refresh, credential-file discovery
or extra Twilio authentication modes. Preserve the existing API-key and Account SID/Auth Token
boundaries. Platform S3 credentials remain platform configuration and are unrelated to model auth.

## Verification

The inventory compares the reference source tree, existing project tests and the current closed
catalog. It corrects the milestone's speculative OpenAI/OpenRouter examples and the stale profile
setup instructions in [context compaction](../docs/context-compaction.md#provider-native-fallback).
The [inventory labnotes](20260915-2351-existing-provider-inventory.md) record independent
review and documentation checks. Recording this inventory completes no provider migration.
