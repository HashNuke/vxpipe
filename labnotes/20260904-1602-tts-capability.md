# Deepgram Flux TTS capability

## Objective

Implement the first complete text-to-speech vertical slice for Vxpipe using
Deepgram Flux TTS streaming only. A participant utterance already travels from
browser WebRTC audio through Flux STT and the deterministic text capability. The
new slice must carry the resulting text through Flux TTS and deliver audible,
paced Opus RTP to that same browser connection.

This checkpoint deliberately does not add Aura, an LLM, local synthesis,
standalone VAD, or interruption handling. It does establish protocol seams that
allow interruption and additional providers to be added without coupling the
room authority to Deepgram or WebRTC.

## Sources reviewed

All of the requested Deepgram documentation was reviewed on 2026-09-04:

- Models and languages: <https://developers.deepgram.com/docs/tts-models-languages-overview.md>
- Flux TTS quickstart: <https://developers.deepgram.com/docs/flux-tts/quickstart.md>
- Feature overview: <https://developers.deepgram.com/docs/flux-tts/feature-overview.md>
- Client messages: <https://developers.deepgram.com/docs/flux-tts/client-messages.md>
- Server messages: <https://developers.deepgram.com/docs/flux-tts/server-messages.md>
- Interrupt handling: <https://developers.deepgram.com/docs/flux-tts/interrupt-handling.md>
- State: <https://developers.deepgram.com/docs/flux-tts/state.md>
- Context: <https://developers.deepgram.com/docs/flux-tts/context.md>
- Encoding details used to resolve PCM byte order:
  <https://developers.deepgram.com/docs/tts-encoding>

The existing Rime TTS implementation in Callpipe/Callx was also reviewed:

- `lib/callpipe/callx/adapters/tts/rime.ex`
- `lib/callpipe/callx/tts.ex`
- `lib/callpipe/callx/audio_frame.ex`
- `lib/callpipe/callx/media_engine.ex`
- `lib/callpipe/callx/media_engines/direct.ex`
- the provider adapter, room media routing, and room capability routing tests

## Flux TTS protocol findings

### Connection and format

Flux TTS is Deepgram's recommended model family for new conversational English
applications. Its streaming endpoint is `wss://api.deepgram.com/v2/speak`, with
authentication supplied in an `Authorization: Token …` header. The required
model name has the form `flux-{voice}-{language}`; the initial Vxpipe default is
`flux-haley-en`.

Streaming output is raw audio and has no file/container header. The streaming
encodings are `linear16`, `mulaw`, and `alaw`. Opus, MP3, and other compressed or
containerized output formats are batch-only and are rejected on this WebSocket
endpoint. For this slice Vxpipe requests `linear16` at 48 kHz. Deepgram defines
that format as signed 16-bit little-endian PCM. The browser-facing WebRTC
boundary must therefore frame and encode the PCM to Opus; provider bytes cannot
be passed through as RTP payloads.

Relevant connection query parameters are:

- `model`, required;
- `encoding`, selected as `linear16` here;
- `sample_rate`, selected as `48000` here;
- optional `speed`, `expressivity`, and `mip_opt_out` settings.

Speed and expressivity remain configuration seams rather than part of this
checkpoint. Configuration is validated before a provider connection starts, and
credentials remain runtime settings. Provider configuration inspection must
never reveal the API key.

### Client messages

The v2 streaming client sends JSON text frames. Its control vocabulary is:

- `Speak`: append text to the active turn. The first message begins a turn.
  Callers may send individual LLM tokens or larger chunks. Distinct chunks are
  concatenated exactly, so whitespace is owned by the caller.
- `Flush`: mark the active turn complete and drain its generated audio. A later
  `Speak` begins a pending turn.
- `Interrupt`: cancel the current active turn. An optional playback offset is a
  session-wide, monotonically advancing millisecond position, not a turn-local
  position.
- `Configure`: change speed at the next segment boundary. A success response
  means validation succeeded, not that the setting has already affected audio.
- `Close`: drain queued synthesis, emit session metadata, and close.

A connection is closed after 60 seconds without traffic. WebSocket ping/pong
traffic resets that inactivity timer, so a persistent room-agent TTS connection
needs a keepalive interval below 60 seconds.

### Server messages and audio boundaries

Server JSON text frames are interleaved with binary audio frames:

- `Connected` identifies the request and resolved model.
- `SpeechStarted` appears once per turn before its audio and assigns a
  server-generated `speech_id`.
- binary frames between `SpeechStarted` and the corresponding terminal metadata
  are raw audio for that turn.
- `Flushed` acknowledges that a requested flush has actually reached the active
  turn. It may be delayed behind earlier pending turns.
- `SpeechMetadata` appears once after all audio for a normally completed turn.
  It is the provider's no-more-audio boundary, not a statement that the browser
  has played all audio.
- `SpeechInterrupted` replaces normal speech metadata for an interrupted turn.
  It can contain played duration, spoken text, remaining text, and nested
  generation metadata.
- `SessionMetadata` reports cumulative session values at close.
- `ConfigureSuccess` and `ConfigureFailure` report configuration validation.
- `Warning` is nonfatal. Examples include no active speech, no synthesizable
  text, synthesis retrying, no generated audio, an interrupt already in
  progress, and invalid interrupt offsets.
- `Error` is fatal and is followed by connection closure. Error categories
  include message, data, size, and network failures.

Unknown additive fields must be tolerated. Known messages missing required
identity or boundary fields are malformed. Provider descriptions and arbitrary
metadata are not promoted into Vxpipe domain events. Only bounded provider codes
are retained for diagnostics.

### Provider state and queue behavior

The documented state machine is Idle, Generating, Finalizing, and Closing. A
text chunk is not a speech turn, and chunk boundaries do not drive synthesis.
There is one active turn, while subsequently flushed turns may queue inside the
provider. Deepgram documents no pending-turn limit. Vxpipe must impose its own
small bound and serialize work for predictable memory and cancellation behavior
instead of treating the provider queue as storage.

`SpeechStarted` and `SpeechMetadata` are the reliable audio bookmarks. A
`Flush` sent without active speech produces a warning. The application must not
infer boundaries from binary-frame sizes or silence.

### Context and connection lifetime

Flux maintains acoustic and prosodic model state across `Flush` and `Interrupt`
within one WebSocket session. It does not retain participant audio, participant
transcripts, or LLM conversation context. Starting another connection resets the
model state. A session has a documented maximum duration of one hour in addition
to the 60-second inactivity rule.

This favors a persistent connection owned by the room agent's TTS capability,
not a fresh connection per sentence. Session rollover before the one-hour limit
is left for a later resiliency checkpoint.

### Interruption behavior reserved for a later slice

On barge-in, the client should stop local playback immediately, then send
`Interrupt`; it should not wait for Deepgram's acknowledgement before silencing
the output. Binary audio arriving between the interrupt request and
`SpeechInterrupted` must be discarded. Supplying the session-wide playback
offset lets Deepgram report `text_spoken`, which can repair the LLM's conversation
context.

Flux STT `StartOfTurn` can become the interruption trigger. The first TTS slice
does not implement barge-in, but provider completion and actual playout
completion are kept separate so interruption can later cancel both independently.

## Callx/Rime findings

The useful Callx ideas are:

- keep one provider WebSocket behind a TTS capability rather than opening one
  connection for each text fragment;
- expose a provider-neutral `start_stream`/synthesize/stop vocabulary;
- normalize asynchronous provider output into an audio-frame representation;
- preserve a partial PCM sample when provider frame boundaries split samples;
- sequence generated audio and carry turn/correlation metadata;
- keep text input and the explicit end-of-stream/flush signal separate;
- use fake provider transports in focused tests;
- route media only to authorized connections.

The implementation should not copy these Callx properties:

- the Rime adapter defines another top-level concern inside the same source file;
- runtime environment access and authorization header construction happen too
  close to adapter execution;
- asynchronous casts and provider output do not have an explicit end-to-end
  queue bound;
- raw audio flows through generic room event routing;
- arbitrary provider metadata escapes the adapter boundary;
- a hard-coded trailing-silence duration is added;
- provider generation completion and receiver playback completion are collapsed
  into one `done` condition;
- no PCM-to-WebRTC-codec and paced-RTP boundary is proven;
- cancellation and provider failure semantics are under-specified.

Vxpipe will retain the good persistent-capability and frame-normalization ideas,
while making backpressure, ownership, transport encoding, and completion
semantics explicit.

## Architectural decision

The room authority remains the domain lifecycle authority. It sequences only
low-rate semantic events and never carries PCM. Provider protocol is owned by the
call engine; WebRTC encoding and RTP pacing are owned by the gateway.

The vertical data path is:

```text
Flux STT final transcript
  -> deterministic text capability
  -> RoomAuthority: TextOutput(will_be_spoken: true)
  -> room-agent TTS capability
  -> persistent Flux TTS WebSocket
  -> normalized 48 kHz mono linear16 frames
  -> authorized connection output sink (direct, bounded handoff)
  -> 20 ms PCM framing and Opus encoding in gateway
  -> paced RTP on the negotiated outbound WebRTC audio track
  -> browser speaker
```

Low-rate acknowledgements travel back in the opposite direction:

```text
first RTP packet sent -> agent speech-started domain event -> RTVI bot-started-speaking
final packet's local schedule elapsed -> agent turn-completed -> RTVI bot-stopped-speaking
```

The provider's `SpeechMetadata` closes synthesis input. It causes the egress
queue to pad at most one final partial 20 ms PCM frame and mark that packet final.
Only elapsing the final paced packet's local duration closes gateway egress.
This prevents the UI from reporting that the bot stopped while audio remains
queued locally. It is not a browser jitter-buffer or output-device
acknowledgement; that would require a future client-side extension.

### Ownership

- `Vxpipe.CallEngine.Provider.TextToSpeech` defines the provider contract.
- a Deepgram Flux TTS adapter validates configuration, creates safe connection
  settings, encodes client controls, and decodes provider controls.
- a separate Flux TTS socket owns the WebSocket and keepalive.
- a room-agent `TextToSpeech` capability owns one provider session, a bounded
  FIFO of synthesis requests, and protocol state.
- `RoomCapabilitySupervisor` starts and stops that dynamic capability.
- each gateway connection owns an `AudioEgress` process beneath its existing
  connection peer supervisor.
- `AudioEgress` owns partial PCM, an explicitly bounded packet queue, the Opus
  encoder, RTP sequence/timestamp state, and the pacing timer.
- the gateway creates an outbound audio track before SDP answer generation, so
  an unmodified RTVI/WebRTC client negotiates reception normally.

### Provider-neutral handoff

The TTS request carries tenant, room, incarnation, participant, connection,
command, and correlation identity plus text and an opaque output-sink pid. The
sink is an internal runtime handle; it is never serialized into a command,
snapshot, event, or public API.

Normalized output describes signed little-endian PCM with sample rate and channel
count. It contains no Deepgram request or speech identifiers. Binary frames are
delivered through a synchronous, bounded call. The WebSocket callback therefore
cannot outrun the downstream egress indefinitely.

Only one request is sent to Deepgram at a time. The next bounded request starts
after the previous request's final audio has actually drained. This avoids an
unbounded Deepgram pending-turn queue and preserves provider context.

### Codec decision

Use Flux `linear16` at 48 kHz mono and encode 20 ms frames to Opus at the WebRTC
boundary. Each frame contains 960 samples and 1,920 PCM bytes. RTP timestamps
advance by 960 per packet and sequence numbers wrap at 16 bits. The first packet
can be emitted immediately; subsequent packets are scheduled every 20 ms without
blocking sleeps.

Direct PCMU pass-through was rejected. Flux can produce 8/16 kHz mu-law, but
choosing it would reduce quality and avoid proving the codec boundary needed by
the intended Opus path. A batch Opus request was also rejected because it loses
streaming latency and is not supported by the Flux streaming endpoint.

The gateway will use libopus through `membrane_opus_plugin`, wrapped behind a
small project-owned encoder module. This dependency belongs only to the gateway,
which owns WebRTC representation. The wrapper localizes reliance on the plugin's
native encoder API and makes that risk explicit.

## Failure and lifecycle rules

- Invalid provider frames fail the capability without forwarding provider text
  or secrets.
- A fatal provider error or closed socket makes TTS unavailable and notifies
  attached connections through the room authority.
- Nonfatal provider warnings do not stop a healthy capability.
- Oversized text, provider JSON, audio frames, or queues are rejected at their
  owning boundary.
- A sink failure fails the affected synthesis path; no false playback-completed
  event is emitted.
- Connection teardown stops its egress and input-media processes through their
  owning supervisors and detaches it from the room.
- Room teardown stops the room-agent provider session through the capability
  supervisor.
- Configuration and `Inspect` output do not expose API keys.

## Red-green implementation plan

1. Add failing adapter tests for validated Flux configuration, redacted
   inspection, `/v2/speak` connection parameters, exact `Speak`/`Flush` controls,
   normal boundaries, warnings, fatal errors, malformed/oversized messages, and
   binary-audio classification.
2. Implement the provider-neutral signal/behavior and Flux TTS adapter/socket.
3. Add failing capability tests proving a persistent socket, ordered
   speak/flush, binary PCM delivery, bounded queued requests, completion only
   after sink drain, warning tolerance, and fatal transport/provider handling.
4. Implement the room-agent TTS capability and supervisor ownership.
5. Add failing egress tests for split PCM samples/provider frames, exact 20 ms
   framing, final padding, bounded input, Opus output, RTP sequence/timestamp
   progression, and paced start/completion acknowledgements without test sleeps.
6. Implement the gateway encoder and per-connection egress.
7. Add failing room/gateway vertical tests proving `will_be_spoken`, raw audio
   bypasses room event routing, answer SDP contains the outbound audio track, and
   RTVI text/speaking events surround actual output.
8. Wire runtime configuration. Resolve one `DEEPGRAM_API_KEY` at runtime when
   either Deepgram input or output is enabled and inject it into both provider
   configurations without logging it.
9. Add an integration-tagged live provider test that receives nonempty PCM and
   terminal metadata. Extend the WebRTC integration lane to prove that Opus RTP
   is received after a spoken input turn.
10. Run focused tests during iteration, then the umbrella completion gates:
    `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`,
    and `mix deps.unlock --check-unused`.

## Deferred work

- barge-in and Deepgram `Interrupt`, including session playback offsets;
- replacing deterministic echo with an LLM capability;
- multiple simultaneous listeners, mixing, and individualized output policies;
- dynamic speed/expressivity configuration;
- provider reconnect/recovery and proactive one-hour session rollover;
- additional TTS providers;
- explicit RTP retransmission/congestion policy and richer output telemetry.

## Verification log

- Adapter tests first failed because the provider-neutral signal and Flux TTS
  adapter did not exist. The implementation now proves redacted configuration,
  the `/v2/speak` query, streaming-format validation, exact client controls,
  bounded JSON/audio, lifecycle decoding, warnings, and fatal errors.
- Capability tests first failed because the TTS capability, request, transport,
  audio frame, and sink contracts did not exist. They now prove persistent
  transport ownership, `Speak` then `Flush`, normalized PCM delivery, one active
  request plus a bounded FIFO, warning tolerance, fatal failure, and delayed
  completion until the sink acknowledges egress.
- Gateway tests first failed because the Opus encoder and audio egress did not
  exist. `membrane_opus_plugin` 0.21.0 was added only to `vxpipe_gateway`.
  Focused tests prove an actual libopus encode, exact 1,920-byte/20 ms PCM
  framing, provider-frame remainder preservation, final zero padding, bounded
  queuing, pacing, and RTP sequence/timestamp progression.
- The first live provider run connected but timed out waiting for
  `SpeechStarted`. The implementation had incorrectly required `request_id` on
  turn messages. The Flux lifecycle examples and the live wire both omit it on
  `SpeechStarted`, `Flushed`, and `SpeechMetadata`; the adapter was corrected to
  require `speech_id` and accept an optional request ID. The repeated live test
  passed with nonempty 48 kHz linear16 audio and a matching terminal speech ID.
- A separately tagged live gateway test passed end to end using a real
  Deepgram session and two ExWebRTC peers. An RTVI `send-text` produced
  `bot-output` with `will_be_spoken: true`, then `bot-started-speaking`, nonempty
  Opus RTP on the negotiated output track, and `bot-stopped-speaking` after the
  local paced queue drained.
- The pre-existing combined live STT test still requires
  `DEEPGRAM_LIVE_AUDIO`. That fixture path was not present in the current shell,
  so its new TTS assertions were compiled but not re-run. The user had already
  verified the live Flux STT input path in the Pipecat UI, while the new
  no-fixture live test independently proves the complete TTS/WebRTC half.
- Final default checks passed from the umbrella root on 2026-09-04:
  `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`
  (32 call-engine tests with one integration test excluded; 24 gateway tests
  with three integration tests excluded), and `mix deps.unlock --check-unused`.
- A final request to the tailnet HTTPS development URL could not connect, and no
  Vxpipe Goreman/Caddy/Vite process was running. The repository checks and live
  in-process WebRTC proof are unaffected, but `bin/dev` must be started again
  before the browser is used for the manual audible check.
