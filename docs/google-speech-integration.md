# Google AI Studio speech integration

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

The Live API limits a session to ten minutes. The adapter prepares a new socket after seven
minutes (or when the provider sends `goAway`) and switches at a completed turn. It fails closed at
9.5 minutes if a replacement cannot be prepared or the active turn never ends. Consequently, one
uninterrupted utterance spanning that expiry cannot be transcribed continuously. This is a known
provider lifetime limit, not a silent restart or cross-call fallback. Setup has a 15-second bound;
replacement failures retry while the active socket remains usable.

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
