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
The extra compatibility machinery from the earlier Go implementation has been
removed, including external codecs, token issuance and TTS WebSockets.
The [scope review](../labnotes/20261015-0057-morse-scope-simplification.md) records
this change separately from implementation progress.

## Verified local handoff — 2026-10-15

| Item | Verified value |
| --- | --- |
| Go source | `HashNuke/morsecode-audio`, revision `1d815f5` |
| Vxpipe acceptance source | `morsecode-api`, revision `7c9b8a4e` |
| Production image | `sha256:581f4a5f0395510fffde6f52b70ddbb3fb3d6a24ffe711d4b1e6ecae859bb8cb` |
| Container check | Read-only, nonroot, 512 MiB, injected `PORT=9876`; HTTP/WS smoke passed and SIGTERM exited 0 |
| Vxpipe local origin | `http://127.0.0.1:18796`; four provider checks, two configured-room checks and persisted TLS/switch/outage acceptance passed |
| Regression | 3,841 Vxpipe tests, zero failures; Go vet and 35-test/subtest race lane passed |
| Hosted origin | `https://morse-audio.definerun.com`; pending the user's Railway deployment |

The temporary test servers, container and fixture database have been retired.
Start your own local server using any free port; these commands use 8787:

```sh
# In the Go repository:
HOST=127.0.0.1 PORT=8787 go run ./cmd/morsecode-audio

# In a second terminal, from the Go repository:
go run ./cmd/smoke -base-url http://127.0.0.1:8787

# In Vxpipe:
MORSE_CODE_API_BASE_URL=http://127.0.0.1:8787 bin/dev
```

Use the ordinary service setup to select `morse_code_api`, enter any nonempty
compatibility key and select its Morse TTS/STT models in the call spec. Both
speech directions stream PCM through the existing scoped session machinery.

Follow the Go repository's
[Railway runbook](https://github.com/HashNuke/morsecode-audio/blob/main/docs/railway-deployment.md)
to deploy. Run the same smoke command with the generated or custom HTTPS origin,
then set Vxpipe's runtime URL and restart its existing process after draining
calls. No credential or call-spec migration is needed. Rollback restores the
previous verified origin; for localhost, start the Go server there first. No
hosted deployment or hosted image rollback target exists yet.
