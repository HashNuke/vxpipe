# Provider expansion and gateway

## Existing live providers — 2026-09-30

Mix PubSub can now open its local socket. The fixture helper passes 4/4.
Root live runs need `PGHOST=/var/run/postgresql` on this workstation; without
it database startup fails before provider requests. Credentials are loaded only
by the authorized runner; the private env file is never inspected or edited.

Gemini passed its three live tool-schema, transfer and cancellation tests using
`gemini-3.5-flash-lite`. Deepgram CallEngine passed 2/2 (Flux TTS and CloseStream
probe). Gateway initially passed 1/3: direct Opus and RTVI microphone tests
never observed EndOfTurn. The generated speech sample lacked silence after the
final word. Added a two-second PCM silence tail to new fixtures (red regression
then 4/4 green). Padded the already-generated public phrase sample and rebuilt
Opus locally, avoiding another TTS request. Both previously failing Gateway
cases then passed individually (1/1 each). Samples contain only the fixed
public test phrase; they remain available for review and commit.

OpenAI initially failed 2/2 after connecting. The direct hosted reseed harness
omitted the consumer history-barrier acknowledgement; production rooms already
provide it. After adding the acknowledgement, the selected live reseed test
failed promptly instead of waiting 110 seconds. Official GPT-Live conversation
docs require assistant startup history to use `output_text`, while our shared
published history emits `input_text`. Added a codec regression and confirmed
it failed, then mapped assistant history at the OpenAI wire boundary. The
common published-history representation remains unchanged. Also added a
local stopped-transport reseed check (passed) and two seconds of input silence
in the hosted harness. Live backend model changed to `gpt-6-luna`, as recommended
by the current OpenAI delegation guide; tool prompt explicitly states when to
delegate. Local/live results after the codec fix are pending.

Sources: https://developers.openai.com/api/docs/guides/live-conversations and
https://developers.openai.com/api/docs/guides/live-delegation.

## Model and route research

DeepSeek now advertises `deepseek-flash` (V4.1 Flash), newer than the installed
LLMDB snapshot. Preserve the wire ID when supplying reviewed metadata for this
model. OpenRouter has `google/gemini-3.5-flash-lite`. Fireworks Gemma 4 listings
require dedicated on-demand deployment; Nemotron Lightning 3.5 30B A3B is
serverless and costs $0.05/M input, $0.20/M output in its official catalog.
Cloudflare's current REST API supports chat completions with a Cloudflare
Workers AI Read token and `cf-aig-gateway-id`; its native Deepgram proxy and
Workers AI Flux routes have distinct authentication and must be verified
independently. At this research checkpoint, new-provider acceptance was still pending.


## Selected direct-provider acceptance and gateway correction

DeepSeek, OpenRouter and Fireworks each passed the shared bounded live contract:
one streamed tool call with validated arguments, one continuation, and reported
usage. Each request caps output at 256 tokens. OpenAI hosted reseed/mute/talkover
passed individually in 12.7 seconds; delegated-tool/spoken continuation passed
in 7.3 seconds. Its new LLM test exposed an obsolete chat-completions wire for
`gpt-6-luna`: the API rejects tools plus reasoning there. A focused red-green
selection test now preserves the Responses wire and `max_output_tokens`; the
selected live rerun is pending.

An experimental Cloudflare LLM request passed. Its Workers AI Flux socket became
ready but closed after the initial audio frame; this is not accepted speech
support. On 2026-09-30 the user clarified gateways are a separate concept and
Cloudflare implementation is deferred. Removed the uncommitted Cloudflare
provider/credential adapter, model dispatch, speech wrapper, registry/catalog/UI
entries and tests. Preserved direct-provider changes and existing live repairs.
Recorded Cloudflare/Vercel gateway routing as an unchecked design milestone.
No further gateway live calls will run in this checkpoint.

The updated objective adds Cartesia STT/TTS and ElevenLabs STT/TTS/agent STS.
These require protocol and room-contract review before implementation; the
provider expansion checklist now records them as pending. The original private
live credentials file has not been read or changed.


## Direct-service checkpoint verification

OpenAI's selected Responses LLM test passed 1/1 in 8.0 seconds after the wire
fix. ReqLLM still warns about current Luna catalog metadata in its internal
lookup; the real tool call, continuation and usage succeed. This warning is
not suppressed globally or used to invent pricing.

A new Console-owned DB test initially failed because demo model readiness only
accepted Google/Zenmux. Extended the fixed demo catalog for direct providers.
A second failure revealed Fireworks validation selecting a catalog-wide default
output bound rejected by its non-streaming validation. Added a focused default
bound regression (red) and set new direct providers to 4096 tokens when the
caller omits a bound. Explicit limits remain unchanged. Selection passes 8/8;
Console demo tests pass 7/7, covering platform inheritance, exact published
provider/model binding and tenant override for each new service.

The UI suite initially failed an older exact installed-provider list; updated
its expectations for the three new services. Fireworks has no verified
credential-only probe. A new form regression failed before disabling Test
credentials and explaining that Save remains available. Form tests pass 16/16.
Chrome Storybook inspection at 1440x1000 (platform DeepSeek) and 390x844
(tenant Fireworks/OpenRouter) shows one password field and no horizontal
scrolling. These are rendered UI checks with synthetic state, not production
browser persistence. The impeccable finish review is pending.

Root warnings-as-errors compile passed. Strict Credo initially reported the
expanded PlanStartup guard exceeding the 800-line limit; a fixed provider
module attribute removes the unnecessary multiline repetition. Strict Credo
then passed (1143 files, no issues). Lean verification passed, including its
one transition-replay test. Unused-lock check passed. The first root suite
exposed one stale fake-socket assertion for assistant input_text; updated to
output_text. A focused rerun also exposed a 100ms wire-start allowance under
concurrent load; use a bounded 1000ms acknowledgement wait. The repaired
41-test GPT-Live session/capability group passes. Final root rerun remains.

The impeccable finish review returned ship, with persistence and fidelity checks
passing and no material fixes. Its visual evidence is scoped to the supplied
desktop and mobile modal screenshots (`.impeccable/review/provider-desktop.png`
and `provider-mobile.png`): this ordinary extension retains the canonical dark
admin modal, selector, field and action styling for DeepSeek, OpenRouter and
Fireworks. Each uses one private API-key field; Fireworks disables Test credentials
with a factual explanation while Save remains available. These screenshots show
prototype browser state, not production persistence. No durable design change or
new design sidecar is needed.


The first whole root run (seed 412687) completed with three failures: the
repaired GPT-Live expected wire content, one Twilio custom-URL destination-loss
recovery timeout, and an older exact Console provider-capabilities expectation.
The last expectation now includes the three new provider declarations. The
Console services/demo group passes locally; the Twilio harness's five selected
cases also pass, but its full-suite timeout cause remains unconfirmed. A second
root run uses the same seed, rather than hiding the failure by selecting another
order. No final all-green root acceptance is claimed yet. Frontend check/lint
pass; its full suite passes 202 tests. The independent UI finish review returned
ship and no material fixes for the narrow extension.


The same-seed second root run is still in progress. It exposed a different
pre-existing completion-order race: Deepgram FluxTextToSpeechSessionTest's
completed-playback case acknowledges provider completion and settles output,
then its next Session.speak returns busy. The current suspect is the previous
asynchronous TTS input operation still awaiting its channel result after
completion/settlement; no repair is implemented or accepted yet. Investigate
with a deterministic held-input-completion regression at the channel boundary
before changing runtime. Do not claim the broad suite passes from the focused
41-test GPT-Live result or the five passing Twilio reruns.

Selected live requests are finished; no billable request remains running.
The gateway design correction is complete locally. Direct service checkpoint
commits/push are still pending final root acceptance. User's unrelated
vxpipe-docs/src/content.config.ts modification remains untouched.

## Later checkpoint status

The TTS callback-order repair is now committed with deterministic success,
failure and deadline evidence; shared speech/opening-audio checks pass 318 tests.
Opening-audio telemetry is scoped to its lifecycle, and STT initialization tests
consume the denied allocation's start notification before selecting restoration.
The latest focused STT file passes 23 tests. Phone scenarios now isolate tenant,
service and ingress identities; their selected harness group passes 27 tests.
These repairs are recorded in their own checkpoint labnotes and detailed commits.

The opt-in runner shell contract passes, and current default-suite results exclude
all live modules. The current root run loaded the STT test before its last fixture
correction and has one known failure; final umbrella acceptance is still pending.
No additional billable request was made during these local repairs.

Cartesia and ElevenLabs remain design/implementation work. Their current protocol
review records Cartesia automatic semantic turns and request-owned phrase TTS,
plus unresolved ElevenLabs STT turn authority and agent STS configuration. The
gateway milestone now distinguishes model identity, inference host and client
wire protocol across Cloudflare and Vercel. Gateway implementation remains deferred.
