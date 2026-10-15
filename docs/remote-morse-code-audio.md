# Hosted Morse audio design

The user's clarified requirement is the existing Morse TTS/STT behavior hosted
in a separate Go application, with ElevenLabs-shaped speech requests and streams.
It is not a reimplementation of the ElevenLabs speech platform. The
[milestone](../labnotes/milestones/remote-morse-code-audio.md) owns the supported
route/profile list and remaining work.

Vxpipe uses one `Vxpipe.Providers.MorseCodeApi` provider with conventional
`TTS`/`TTSSession` and `STT`/`STTSession` components, just as other adapters
do. The example concatenated names are not a requirement. Existing local Morse
and ElevenLabs providers stay independently selectable.

The Go service owns Morse encoding/decoding, HTTP/WS transport and request
lifecycle. It accepts arbitrary nonempty `xi-api-key` values, keeps active
processing in bounded memory and requires no account system or storage.
Vxpipe continues to store its configured credential through the normal encrypted
service mechanism. Compatibility keys are not an access-control boundary.

Use the local Morse alphabet and timing: 700 Hz, 60 ms dot, amplitude 4096,
1/3-unit marks, 1/3/7-unit gaps and 14-unit final silence. Exchange mono PCM,
with 16 kHz on the ordinary room recognition path. Recognition is for Morse
tones. Go performance should be checked through bounded processing and practical
round trips, not inferred from the language or made contingent on an elaborate
load-study target.

`MORSE_CODE_API_BASE_URL` is Vxpipe runtime configuration. It determines
discovery, service probes, TTS HTTP and STT WebSocket destinations. Derive WS/WSS
from HTTP/HTTPS; retain normal certificate verification and never fall back to
another origin. The endpoint belongs outside call specs and credentials so
switching it requires only configuration and restart.

Run the standalone server locally first. Prepare its small container and Railway
runbook, then let the user deploy to `morse-audio.definerun.com`. Go listens on
`0.0.0.0` and Railway's injected `PORT`; Vxpipe uses the public HTTPS origin.
Local preparation and actual hosted acceptance are recorded separately.

Rejected approaches:

- Complete ElevenLabs API/SDK parity: exceeds the clarified request.
- Browser tokens, multi-context TTS, compressed format matrices, retention or
  asynchronous job machinery: unnecessary for the PCM Morse provider.
- A new generic provider abstraction or room state machine: existing adapters,
  scoped sessions, backpressure, cancellation and policy handling already own this.
- Calling Vxpipe's local codec instead of the Go server: would not exercise the
  remote provider the user requested.

The current implementation has working remote speech and provider integration.
Historical acceptance is recorded in the
[STT integration note](../labnotes/20261015-0019-morse-stt-integration.md) and
[origin/restart note](../labnotes/20261015-0036-morse-origin-restart.md).
The earlier Go implementation includes extra compatibility machinery that now
needs pruning; it must not be expanded simply because it was planned earlier.
The [scope review](../labnotes/20261015-0057-morse-scope-simplification.md) records
this change separately from implementation progress.
