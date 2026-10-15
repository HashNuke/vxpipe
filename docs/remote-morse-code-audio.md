# Hosted Morse audio design

Vxpipe uses one `Vxpipe.Providers.MorseCodeApi` provider with conventional
`TTS`/`TTSSession` and `STT`/`STTSession` components. The independent Go service
encodes text into Morse PCM and recognizes Morse PCM as text. It does not
recognize human speech or call ElevenLabs. Both realtime directions follow the
relevant ElevenLabs WebSocket message conventions.

The public endpoint is **https://morsecode.vxpipe.com**, deployed to Railway
with 0.5 vCPU and 125 MB memory. The service keeps active work in bounded memory;
there is no database, retained audio, transcript history or account system.
Vxpipe's existing service form still stores a compatibility credential through
its normal encrypted mechanism; that value does not grant access to this public
API. The TTS WebSocket adapter sends no credential header.

## Speech boundary

Realtime TTS uses `/v1/text-to-speech/morse/stream-input`. Initialize with
`{"text":" "}`, submit text fragments, and send `{"text":""}` at end of input.
Read base64 `audio` frames while sending; only `isFinal: true` completes the
stream. `flush: true` finishes an utterance but keeps the socket available for
more text. Fragment boundaries preserve letter/word spacing; only flush/EOS adds
the 840-ms final silence. HTTP TTS remains available for direct callers.

Vxpipe's current `speak` contract accepts a complete utterance. Its request task
uses the WebSocket protocol for that utterance and consumes audio incrementally
under the existing output-credit mechanism. It does not yet expose an incremental
LLM-token input interface. Cancellation kills the owning task and closes its
socket even while waiting for output credit. An early close without `isFinal`
is a failure, never successful completion. No HTTP fallback or automatic retry
can duplicate audible output.

Realtime STT uses `/v1/speech-to-text/realtime`. It emits `session_started`,
cumulative `partial_transcript`, and final-segment `committed_transcript` events.
Optional timestamps add `committed_transcript_with_timestamps` after the ordinary
commit. Partials arrive after Morse letter gaps. Manual commits and silence-based
automatic commits use the same final event. There is no separate `turn_ended`,
`speech_started` or `final_transcript` wire event in this supported protocol.
Vxpipe retains its own transcript-onset and room-turn behavior. A provider commit
alone does not prove conversational turn completion.

Use 700 Hz, 60-ms dots, amplitude 4096, 1/3-unit marks, 1/3/7-unit gaps and a
14-unit final silence. This is 20-WPM International Morse using the PARIS speed
standard; the final padding is specific to this API. Exchange mono PCM16 at
8/16/24/48 kHz, with 16 kHz on the ordinary recognition path.

## Configuration and deployment

`MORSE_CODE_API_BASE_URL` is read in `config/runtime.exs` and selects discovery,
service probes and both speech sockets. Derive WS/WSS from HTTP/HTTPS, preserve
certificate verification and never fall back to another origin. The endpoint
stays outside credentials and published call specs. Drain calls, change the
variable and restart to switch origins; rollback uses the same process.

```sh
# Go repository, local server:
HOST=127.0.0.1 PORT=8787 go run ./cmd/morsecode-audio
# Vxpipe, local adapter:
MORSE_CODE_API_BASE_URL=http://127.0.0.1:8787 bin/dev
# Hosted Vxpipe configuration:
MORSE_CODE_API_BASE_URL=https://morsecode.vxpipe.com bin/dev
```

Railway runs one nonroot Go container on `0.0.0.0` and its injected `PORT`.
See the [deployment runbook](https://github.com/HashNuke/morsecode-audio/blob/main/docs/railway-deployment.md),
[public reference](https://morsecode.vxpipe.com/llms.txt),
[realtime TTS contract](https://github.com/HashNuke/morsecode-audio/blob/main/docs/realtime-tts.md)
and [load-test guide](https://github.com/HashNuke/morsecode-audio/blob/main/docs/load-test.md).

## Decisions and verification

Reuse the existing encoder and scoped request/session machinery. The Go stream
encoder carries spacing and counters across fragments, rather than retaining or
regenerating the whole utterance. Eight TTS sockets/HTTP requests share admission
capacity; STT has a separate 64-socket pool. These are configured limits, not
universal throughput guarantees. Test paced concurrency separately from burst
throughput and distinguish 429 admission control from protocol failures.

Rejected approaches: complete ElevenLabs platform/SDK parity, compressed audio,
alignment, multi-context synthesis, browser tokens, retained jobs, a new generic
provider abstraction, and a second room state machine. They exceed the requested
Morse speech boundary. Calling the local codec instead of the remote service
would fail to exercise the integration.

The [original milestone](../labnotes/milestones/remote-morse-code-audio.md)
records the completed HTTP-TTS/WS-STT baseline. The
[realtime synthesis milestone](../labnotes/milestones/realtime-morse-synthesis.md)
tracks the WebSocket TTS follow-up and hosted acceptance. Its
[labnote](../labnotes/20261015-0500-realtime-morse-synthesis.md) records red/green,
room, interoperability and regression evidence. Historical local acceptance is
also recorded in the [STT note](../labnotes/20261015-0019-morse-stt-integration.md)
and [origin/restart note](../labnotes/20261015-0036-morse-origin-restart.md).
