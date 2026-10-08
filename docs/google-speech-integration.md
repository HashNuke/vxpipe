# Google AI Studio speech integration

Current configured slice, 2026-10-07: the Google manifest now advertises STS
with `gemini-3.8-live`, the existing saved Google key, and public voice/turn
control. See [Gemini provider acceptance](milestones/gemini-live-provider-acceptance.md)
for live evidence and outstanding checks. Gating statements in the historical
checkpoints below describe their source revision, not current selection.

## Decision

Vxpipe exposes Google AI Studio as two independent scoped speech capabilities. TTS uses the
Interactions API with `gemini-3.1-flash-tts-preview`; STT uses the Live API's dedicated
`gemini-3.5-transcribe-live` model. The public call-spec selections are `provider: "google"` with
those model names. TTS accepts `options.voice` (default `Kore`) and emits mono 24 kHz PCM16. STT
accepts mono 16 kHz PCM16 and emits provider `voiceActivity` speech-start and turn-end evidence
with interim and final input transcription. The provider implementations are
`Vxpipe.Providers.Google.TTSSession` and `Vxpipe.Providers.Google.STTSession`; wire/request helpers
remain private. Credentials resolve from the existing tenant or platform service binding and are
never call-spec fields.

The engine keeps one speech allocation under the relevant call/participant tree. TTS request tasks
run under that allocation's command supervisor. The active and replacement STT sockets run under
its provider supervisor; a replacement socket's failure is monitored and retried without taking
down the healthy active socket. Active socket failure closes only that allocation. No common
cross-call speech supervisor, alternate provider, or legacy adapter is involved.

## Turn and lifetime rules

Google's Live API can send `ACTIVITY_END` before the final input transcription, and the next
activity can start before that final arrives. The adapter correlates the oldest pending ended turn
with its final text. It emits `turn_ended` only after both facts arrive, keeping barge-in tied to
the earlier `ACTIVITY_START`. A bounded queue rejects ambiguous accumulation. It does not invent a
silence timer or treat a partial transcript as a turn boundary.

The speech-recognition adapter retains its earlier conservative socket schedule:
prepare a new socket after seven minutes (or on `goAway`) and switch at a completed turn. It fails closed at
9.5 minutes if a replacement cannot be prepared or the active turn never ends. Consequently, one
uninterrupted utterance spanning that expiry cannot be transcribed continuously. This is a conservative
STT adapter lifetime policy, with no silent restart or cross-call fallback. Setup has a 15-second bound;
replacement failures retry while the active socket remains usable.

These STT rules do not define the Gemini STS lifetime. The conversational adapter
uses server-side sliding-window compression and `goAway`-driven resumption without
local connection-age timers; see [Gemini Live session lifecycle](gemini-live-session-lifecycle.md).

TTS sends one complete text request, reads bounded streaming PCM deltas, and publishes one chunk
at a time only after exact Channel credit. The task can be killed on cancellation; its generation
cannot deliver output to a later request. A provider completion event is required after all audio
credits. A failed or timed-out request closes its scoped capability without claiming success.

WebRTC's existing speech input path decodes Opus into the selected STT PCM format. The telephony
path now converts Telnyx Opus 16 kHz and Twilio μ-law 8 kHz into mono PCM16 16 kHz for Google STT,
while the room-audio path keeps its original frame. The telephony normalizer belongs to its media
session and is replaced when the speech ingress changes. Stereo Opus input remains the separate
[deferred issue](issues/webrtc-opus-stereo-input.md).

## Alternatives and implications

General Gemini inference and ordinary audio-understanding responses do not supply the dedicated
speech-start and turn-end contract required by conversational STT. A transcript-only timer would
weaken barge-in and endpointing. Restarting every speech turn would add setup latency and risk
misplacing a late final. The prepared replacement socket keeps the old turn intact until it
finishes. The unavoidable hard expiry is surfaced as failure rather than hiding a gap.

Google TTS has a fixed PCM output format, so the voice controls the provider request but does not
change the call engine's audio descriptor. Google STT does require media conversion at telephony
and WebRTC boundaries; admission fails on unsupported source formats. Saved service credentials
and database schema are unchanged.

## Verification

The saved platform key passed local live probes without printing secrets, audio or transcripts.
One TTS adapter run returned 27 streamed chunks (51,840 PCM bytes), first audio in 2,360 ms and
completion in 5,216 ms. A two-turn STT session admitted all 73 synthetic input chunks and returned
two starts and two finals; a second two-turn run switched to a prepared socket between turns and
again returned two starts and two finals. These are interoperability samples, not production
latency guarantees.

Focused tests cover request framing, per-chunk credit, cancellation, provider failure, STT turn
ordering, replacement failure, active socket loss, inline activation, room barge-in and phone audio
conversion. A bounded synthetic run used four BEAM schedulers, 16 sessions per lane and 20 turns
per session: 320/320 TTS and 320/320 STT turns completed after the replacement-socket fix.
Google session-local p99 was 2.220 ms from TTS request to completion, 2.274 ms to settlement,
0.547 ms for STT audio admission and 0.942 ms for STT turn end. The comparable Deepgram TTS
fixture at the same bound completed 320/320 requests, with 2.669 ms completion and 3.536 ms
settlement p99. These fixtures differ;
the result only shows no observed local delivery degradation or dropped turn at this load. Vendor
network latency is separate.

Sources: [Google speech generation](https://ai.google.dev/gemini-api/docs/speech-generation),
[Interactions streaming](https://ai.google.dev/gemini-api/docs/streaming),
[Live transcription](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe), and
[Live API reference](https://ai.google.dev/api/live).

## Google as agent-output recognizer

The `output_speech_to_text` slot reuses ordinary STT adapter resolution, public
option validation, host enablement and tenant credential lookup. It does not add
a provider manifest capability or a separate credential/settings namespace.
`SpeechToSpeechRuntime.output_speech_to_text` remains the public provider tuple;
`output_speech_to_text_private` separately retains the existing STT runtime's
config and transport options. Runtime inspection excludes that private field.
Room allocation forwards it through the existing sidecar PrivateInit handoff.
The generator's private configuration remains separate and unchanged.

The earlier synthetic-credential fake-wire checkpoint started the selected Google
recognizer under the agent tree with matching 16 kHz fixture formats. That proved
private startup wiring, not finite-input terminal support. Current startup rejects
Google as an output recognizer before credential lookup/allocation: its ordinary
STT adapter does not implement `finite_input?`/`finish_input` terminal proof.
Fake-wire tests retain private credential delivery, setup model, status redaction
and cleanup for independent human Google STT. Host/tenant gates remain intact.
Private sidecar fields/handoff remain in place for future supporting adapters.

PlanStartup now rejects incompatible generated-output/recognizer-input formats
before room or recognizer allocation and before resolving private credentials.
The pure output-STT helper obtains both public descriptors from the existing
catalog/configure boundary, reuses shared Descriptor validation, and requires
exact format equality (encoding, container, rate, channels, byte order and
signedness). It compares STS output `format`, never microphone `input_format`.
Human STT is independent. No conversion or silent selection rewriting occurs.
For example, Google STS declares 24 kHz output and Google STT requires 16 kHz;
those descriptors are incompatible even though their microphone-input rates
coincide. This does not enable Google STS selection.

Hosted finite-input terminal support and overall output-route acceptance remain
explicit open requirements. Per-segment final text is not proof that every segment
from one generated reply has arrived. Direct low-level sidecar allocation also
rejects missing terminal capability; its PCM validation remains a separate boundary.
No generated audio is submitted by this probe; no hosted call or Google STS
manifest enablement is claimed. See
`labnotes/20260922-1721-output-stt-private-config.md` and
`labnotes/20260922-1815-output-stt-format-admission.md` for historical red-green methods,
and [the finite-input settlement decision](output-recognition-settlement.md) for
the current admission contract. No Google protocol behavior was changed here.

## Raw STS server voice activity

The codec accepts top-level `voiceActivity` with raw `type` values
`ACTIVITY_START`, `ACTIVITY_END`, or `TYPE_UNSPECIFIED`. The first two produce
the existing private adapter activity events; omitted/unspecified type produces
none. Optional `audioOffset` must be a UTF-8 string within the existing 65,536-byte
text bound. It is validated but is not interpreted as playback or settlement time.
Malformed known fields and SDK-only aliases (`voiceActivityType`,
`voice_activity_type`, `audio_offset`) fail with `:invalid_message`, including
when supplied alongside valid raw fields. No partial events escape a failed decode.

The pinned Python SDK's [actual receive path](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/live.py#L549)
invokes the MLDev [raw `type` converter](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/_live_converters.py#L2026).
SDK-facing `voiceActivityType` is not a second accepted wire spelling. Invented
`serverContent.activityStart`/`activityEnd` fields are no longer interpreted;
client encoders remain unchanged. The allowlisted detection signal and deprecated
speechState are not fallback boundaries. This checkpoint proves codec behavior
and migrated fake-wire fixtures. The subsequent [STS controller checkpoint](google-sts-controller.md)
adds actual capability/sink proof of caller-end streaming admission, bounded
fragment assembly, output-text source isolation and separate generation/playback
settlement. It also prevents playback from making an unfinished model turn a
resumable idle checkpoint. Overlapping caller/response correlation, caller final
text, interruption-history repair and hosted acceptance remain open.
The local Google STS profile now rejects hybrid before startup. Provider and
external control retain their distinct automatic-detection settings; duplicate
external boundaries and idle ends are idempotent. This does not validate the
still-open interruption encoder/history path or enable the manifest entry.

## Private STS activation configuration

Local implementation checkpoint, 2026-09-22; Google STS remains unadvertised and
public selection remains gated. The hosted evidence above concerns the separate
STT/TTS integrations, not Gemini STS acceptance.

`PlanStartup.SpeechToSpeechActivation` resolves the pinned agent prompt and uses
the existing `AgentRuntime.ToolDescriptors` compiler for the configured tool
allowlist and authorized Call Variables actions. It retains only each tool's
name, description and input schema. Invocation bindings, variable values and
executable handlers never enter provider configuration. Variable permissions
require the existing activation binding; remote MCP tools fail explicitly because
this startup path has no owning MCP runtime. This checkpoint does not create that
owner, execute tools, change invocation lifetime or start a text-model session.

`SpeechToSpeechRuntime` splits public model/voice/turn-control settings from the
private Google config. That config contains the resolved credential, instruction
and declarations. `PlanStartup`, activation and Google config inspection redact
the private contents. Provider status and failure logs also redact them. The
existing private-init handoff and retained resumption config carry these values;
no capability/room runtime or resumption algorithm change is required.

The wire encoding follows Google's [Live setup reference](https://ai.google.dev/api/live#bidigeneratecontentsetup):
`systemInstruction.parts[].text`, `tools[].functionDeclarations`, and activity
detection nested under `realtimeInputConfig`. Each declaration uses
[`parametersJsonSchema`](https://ai.google.dev/api/generate-content#FunctionDeclaration)
to preserve the authorized JSON schema exactly. It does not convert schemas to
Google's separate OpenAPI-shaped `parameters` representation. The same validated
setup is sent after private handle renewal, with only `sessionResumption.handle`
changed. No history/audio/tool replay or fresh-session fallback is added.

Local bounds are 65,536 UTF-8 prompt bytes, 64 declarations and 131,072 bytes for
the combined prompt/declarations, checked both as an Erlang external term and
as encoded JSON (including escaping). Existing descriptor limits additionally
bound tool names, descriptions and individual schemas. Schemas must be valid
JSON objects describing an object, pass the existing schema compiler and round
trip through JSON without changing values. Unknown declaration fields, duplicate
names/options, public prompt/tool options, non-object schemas, unavailable
bindings and invalid/oversized input return sanitized configuration errors.
Session startup revalidates private structs before connecting, including the fixed
endpoint. These are adapter bounds, not claims about Google's maximum capacity.

Rejected alternatives: dropping schemas or unsupported bindings would silently
change the agent's allowed tools; retaining complete descriptors would retain
execution authority unnecessarily; placing prompt/tools in public descriptors
would expose private content. A second LLM session would split conversational
ownership. Google non-blocking behavior overrides and built-in tools are not
accepted by this declaration-only configuration path.

Verification: 88 focused startup/selection, Google codec/session and shared STS
conformance/output tests pass (seed 0, two schedulers). Fake-wire checks assert
exact initial/resumed instructions and parameter schemas, no replay, empty
allowlists, redaction and pre-connect rejection. The initial red run was 16 tests
with five failures; later focused reds reproduced tampered config reaching a
socket and the misplaced activity-detection field. Commands and evidence are in
`labnotes/20260922-1650-google-activation-config.md`. No hosted call, registry or UI
enablement, full umbrella/native/load gate or overall milestone acceptance is
claimed by this checkpoint.
