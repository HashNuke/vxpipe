# Cartesia and ElevenLabs speech integration

Local design review and Cartesia STT/TTS checkpoints, 2026-09-30. This document informs
[provider expansion](milestones/provider-expansion-and-ai-gateway.md).
Cartesia STT/TTS have local scoped-service/startup and selected live evidence;
ElevenLabs and the milestone's remaining acceptance checks are pending. The existing
[speech contract](speech-provider-contract.md) and
[session ownership](speech-session-ownership.md) remain authoritative.

## Shared boundaries

Keep credentials and service manifests in `vxpipe_providers`; put vendor speech
configuration, protocol and sessions under their provider directories in
`vxpipe_call_engine`. Console saves the exact API-key credential through the
existing encrypted tenant/platform workflow. Public capability options contain
model, voice, language and audio settings, never credentials, arbitrary endpoints
or executable transport hooks. Tenant overrides and platform fallback retain
their current semantics.

Every speech allocation belongs to the existing capability/session tree. Socket
workers and request tasks have an explicit supervised owner. Provider-private
state, errors and status output redact authentication. Room media is negotiated
as raw mono little-endian signed PCM; codecs and resampling stay at the existing
media boundary. Usage reports provider/model identity and measured accepted text
or audio, without inventing token counts or prices.

AI gateways have a separate [deferred design](milestones/ai-gateway-routing.md).
These integrations must work directly without gateway routing tables.

## Cartesia STT

Use automatic-turn `/stt/turns/websocket` and `ink-2`, with 16 kHz PCM as the
initial tested format. Its current stable model was released September 17, 2026.
[Ink 2](https://docs.cartesia.ai/build-with-cartesia/stt/latest).

Map `connected` to provider-acknowledged readiness and `turn.start` to a fresh
local turn reference. Preserve cumulative transcript updates; never concatenate
updates into duplicated text. Map eager end, resume and definitive end separately.
This is provider semantic endpointing. The API supports close-and-drain for
remaining recognition; finishing finite input must preserve the final turn before
retiring the allocation. [Automatic STT reference](https://docs.cartesia.ai/api-reference/stt/turns/websocket).

Continuous input must include paced silence; stopping audio does not establish a
silence boundary. Reject malformed lifecycle transitions locally, bound pending
events and transcript size, and keep transport failure distinct from final
recognition. Test cumulative text, eager-end/resume, repeated turns, close/drain
and readiness rejection. [Turn guide](https://docs.cartesia.ai/use-the-api/stt/turns).

Reject manual and batch endpoints for this conversational slice. They require
different turn ownership or whole-file input; they are not automatic-turn
alternatives. [Endpoint comparison](https://docs.cartesia.ai/use-the-api/stt/compare-endpoints).

The implemented provider keeps configuration/decoding (`Cartesia.STT`), turn
state (`STTTurns`), socket framing (`STTSocket`) and allocation lifecycle
(`STTSession`) separate. One active local turn and a bounded cumulative transcript
replace a growing provider-turn map. Connection identity must remain stable;
overlap, transcript revision and invalid eager/resume transitions fail closed.
Provider errors and close reasons are excluded from diagnostics.

The initial closed public contract accepts only `ink-2`, raw mono signed
little-endian 16 kHz PCM, messages up to 256 KiB, transcripts up to 64 KiB and
audio chunks up to 32,000 bytes. Authentication stays in versioned Bearer headers.
Optional turn tuning is omitted because the guide and generated SDK disagree on
default thresholds. There is no automatic retry or reconnect.

The socket is a temporary child of the allocation's provider supervisor; its
deferred connection cannot block the session process's initialization. Readiness
requires `connected`. Finite input sends the JSON close command and leaves the
socket open to drain. Only an observed normal/no-status peer close after that
command, with no unfinished turn, permits ordered `input_finished`. EOF, abnormal
close, incomplete turns and the 15-second setup/drain timeouts fail. Local session
close aborts the allocation without claiming successful recognition completion.

Rejected alternatives include treating every segment as a completed turn,
concatenating cumulative updates, using local socket close as drain evidence,
or sharing Google's renewal logic with Cartesia's distinct protocol. Existing
room/media and event acknowledgement boundaries remain authoritative.

One selected live Ink 2 connection passed using the committed public phrase,
under ten seconds of paced speech/silence, preserving its final word before
finite completion. Local session, coalesced real-socket close, compiled session
startup and persisted platform/tenant override checks pass. Root acceptance is
tracked separately in the [STT checkpoint](../labnotes/20260930-0753-cartesia-turn-stt.md).

## Cartesia TTS

The current stable model is `sonic-3.6`; use that explicit model family for the
bounded live test and a documented stock voice, Skylar
(`db6b0ed5-d5d3-463d-ae85-518a07d3c2b4`). The provider accepts a dated snapshot
when an operator needs fixed model behavior.
[Sonic model guide](https://docs.cartesia.ai/build-with-cartesia/tts-models/latest).

Initial complete-phrase synthesis can use streaming `/tts/bytes` with API version
`2026-08-14`, raw `pcm_s16le`, and a supported PCM rate. Each admitted phrase owns
one bounded request task; the semantic session remains reusable across phrases.
Successful HTTP completion means generation completion only after credited PCM
has been accepted. Verify response status/format, alignment, fragmented bytes,
audio limits and empty/error responses. Cancel the exact task and fence its
output so late chunks cannot enter a replacement phrase.
[Bytes reference](https://docs.cartesia.ai/api-reference/tts/bytes).

The alternative native WebSocket has context-scoped chunks and cancellation,
with distinct flush and done events. It is useful for future incremental text.
Do not treat a flush acknowledgement as generation completion or copy another
vendor's persistent-session segmentation policy.
[WebSocket reference](https://docs.cartesia.ai/api-reference/tts/websocket).

The implemented request lifecycle is `Speech.RequestTTSSession`, extracted from
Google TTS. Google and Cartesia retain separate provider configuration and wire
decoders; their session wrappers implement `Speech.RequestTTSProvider` for private
configuration and phrase validation. This shared process owns a single credited
request task, its deadline and exact-request cancellation under the existing
session tree. `Speech.PCMStream` frames bounded raw signed 16-bit fragments.

Rejected alternatives are copying Google's lifecycle into each HTTP provider,
or introducing a generic base for both HTTP and persistent WebSocket protocols.
The extraction applies only to complete-phrase request TTS. It adds no provider
discovery, public transport hooks, gateway routing or dependency reversal.
Google's public session/configuration contract and SSE decoding remain unchanged.

Cartesia service configuration uses one API key. Public call options require a
voice UUID, a reviewed model and optionally 8/16/24/48 kHz PCM (default 24 kHz).
The supported model choices are `sonic-3.6`, its reviewed dated snapshot
`sonic-3.6-2026-08-27`, `sonic-3.5` and `sonic-3`. Each phrase is limited to
1,000 characters/4,000 UTF-8 bytes, with no HTTP retries or redirects, a
60-second request deadline and a 32 MiB response limit. Empty, truncated,
unsupported-format or unsuccessful responses fail without false completion.
Initialization is local readiness, not proof of upstream authentication.
Credential testing remains optional and unavailable for this checkpoint; the
selected live synthesis verifies its key without advertising an unreviewed probe.

Verification: shared session/configuration/framing checks, seven loopback HTTP
checks, compiled startup with credited usage, persisted publication and scoped
credential checks, and one short live Sonic/Skylar request pass. See
[checkpoint evidence](../labnotes/20260930-0705-cartesia-request-tts.md).

## ElevenLabs TTS

Use complete-phrase HTTP streaming and explicit raw PCM. Keep voice selection as
a public capability setting and use a documented stock voice for live acceptance.
The same owned-request, credit and cancellation requirements apply.
[Streaming reference](https://elevenlabs.io/docs/api-reference/text-to-speech/stream).

`eleven_flash_v2_5` is a documented economical realtime test choice. The current
catalog also includes newer `eleven_v4` and `eleven_v4_turbo`; support should
validate reviewed model choices without claiming every model has identical
transport constraints. Confirm voice availability and PCM entitlement in the
selected bounded test before advertising acceptance.
[Model catalog](https://elevenlabs.io/docs/overview/models).

## ElevenLabs STT: turn authority still needs resolution

`scribe_v2_realtime` supports PCM and manual/VAD commit strategies. Its partial
transcripts are replaceable; committed transcripts finalize segments. The server
can commit accumulated audio automatically, including in manual mode. A committed
segment alone cannot prove that a conversational user turn ended.
[Realtime reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime),
[commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies).

Before room admission, specify how speech start and definitive turn end are
established, including long uninterrupted speech and server commits. Options are
verified provider boundary evidence or an explicit local/external turn owner.
The current conversational STT contract requires authoritative endpointing;
do not loosen it silently or label inferred activity as provider-reported VAD.
This question remains open and is not an implemented STT capability.

## ElevenLabs STS: conversational agents and voice conversion differ

Conversational ElevenAgents uses an agent ID and its own conversation WebSocket;
private agents require a server-obtained signed URL. A reusable room integration
must establish initiation overrides, input/output formats, turn and output
identity, interruption, transcript reconciliation, history, client tool results,
agent provisioning and cleanup. Keep signed URLs private.
[Agents WebSocket guide](https://elevenlabs.io/docs/eleven-agents/libraries/web-sockets).

The voice-changer STS models transform existing speech. They do not by themselves
implement Vxpipe's conversational agent STS behavior. Do not register voice
conversion as agent conversation. Product interpretation and the corresponding
agent configuration contract remain pending; STT and TTS work can proceed
independently. [Model catalog](https://elevenlabs.io/docs/overview/models).

## Acceptance sequence

1. Write protocol/configuration tests before each behavior change.
2. Prove owned session readiness, PCM credit, interruption, cancellation, failure,
   privacy and usage locally; then wire compiled room startup and scoped services.
3. Add Console configuration only for supported capabilities and inspect it in
   rendered desktop/narrow states.
4. Add fixed test model/voice choices and credential placeholders; use
   `bin/test-live-providers --only live_cartesia` or `--only live_elevenlabs` with
   a capability-specific file. Never invoke every live provider together.
5. Bound each synthesis phrase and audio sample; reuse the existing public sample
   where appropriate. Explicitly label local fixtures versus live observations.
6. Pass the root completion gates and Lean lane, synchronize milestone evidence,
   and commit coherent checkpoints.
