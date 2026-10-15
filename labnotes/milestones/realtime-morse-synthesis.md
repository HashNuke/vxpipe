# Realtime Morse synthesis

Status: implementation and local acceptance in progress, 2026-10-15.

## Runnable slice and prerequisites

The hosted Morse provider synthesizes over ElevenLabs' single-context input
WebSocket and recognizes over its realtime STT protocol. Vxpipe uses both
through its existing adapter. Prerequisites: the completed
[hosted provider](remote-morse-code-audio.md),
[speech contract](../../docs/speech-provider-contract.md), and
[session ownership](../../docs/speech-session-ownership.md).
The [current design](../../docs/remote-morse-code-audio.md) owns rationale;
[checkpoint labnotes](../20261015-0500-realtime-morse-synthesis.md) own evidence.

## Approved contracts

- TTS initialization space, incremental literal text, optional utterance flush,
  empty-text EOS, base64 PCM frames and camel-case `isFinal` completion.
- Preserve 20-WPM Morse and one 840-ms tail per utterance across fragments.
- Existing Vxpipe `speak` supplies one utterance. Preserve credit, cancellation,
  bounded PCM and failure normalization; do not add an LLM-token input API.
- STT uses session/partial/committed events and optional timestamped commit;
  no invented speech-start or turn-end events. Echo keepalive configuration.
- Configurable origin and verified TLS; public API with no storage.
- Eight TTS slots shared by HTTP and sockets; separate 64 STT slots. Bound
  messages, input, duration, session lifetime and idle/write deadlines.
- Direct HTTP APIs remain available. No multi-context, alignment or MP3 work.

## Checkpoints and acceptance

- [x] Confirm current ElevenLabs input/output and flush/EOS contracts from
  official schemas/guides; record supported differences explicitly.
- [x] Red test fragment timing and audio-before-EOS, then implement bounded Go
  stream encoding and the WebSocket route.
- [x] Verify shared admission, cancellation, shutdown and repeated flush.
- [x] Red test adapter WebSocket exchange, then reuse its supervised request task
  for incremental PCM and completion/cancel/error handling.
- [x] Verify STT wire events including timestamped final and keepalive echo.
- [x] Run independent Go/Elixir PCM interoperability and configured-room
  repeated-turn/interruption acceptance.
- [x] Run persisted origin switch, TLS rejection and outage acceptance.
- [x] Pass Go format/vet/full/race and Vxpipe root/Lean gates.
- [ ] Update public docs, inspect desktop/mobile rendering, and commit/push.
- [x] Deploy exact Go revision; smoke HTTP and both WebSockets on custom domain.
- [x] Run bounded paced STT/TTS concurrency stages; record counts, latency,
  configured limits, admission rejections and workload limitations.

## Design review (separate from implementation)

Reviewed dependency order and protocol ownership against the linked prerequisites.
This extends the completed hosted adapter; it has no dependency on unfinished
container delivery. Transport changes belong in the provider request task,
not room state. Go owns fragment spacing and final padding; Vxpipe owns output
credit and room lifecycle. `isFinal` ends the TTS stream; a flush does not.
STT committed text is a final segment, not a new conversational turn event.
Hosted load results must distinguish configured admission limits from measured
capacity. The index stays unchecked until all acceptance gates pass.
