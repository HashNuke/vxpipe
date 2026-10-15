# Realtime Morse synthesis

## Request and decisions

Add true incremental-input WebSocket TTS, update the MorseCodeApi adapter, retain
ElevenLabs event shapes, deploy and measure realtime capacity. Keep the existing
Morse profile and public, storage-free service. Official TTS schema and guide use
`audio` and camel-case `isFinal`; empty text ends the stream, while `flush` keeps
it open. STT uses `partial_transcript` and `committed_transcript`, not invented
speech-start/turn-end events. Optional timestamped commits are additional data,
not another turn.

Sources:
- https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-stream-input
- https://elevenlabs.io/docs/eleven-api/guides/how-to/websockets/realtime-tts
- https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference

Reuse the Go encoder per fragment, carrying only spacing/counters and deferring
its tail to flush/EOS. Eight connected TTS sessions share capacity with HTTP;
STT remains separate. Reuse Vxpipe RequestTTSSession, credit and cancellation.
The current `speak` contract supplies a whole utterance over the WebSocket;
this does not introduce a token-by-token LLM interface. Explicit final completion
prevents a truncated socket from looking successful. No retries or HTTP fallback.

## Red/green and local evidence

- Initial Go stream-encoder tests failed on missing implementation; WebSocket
  route tests failed with 404. After implementation, fragment waveform/timing,
  early audio, flush, admission, disconnect and drain tests pass.
- Vxpipe red tests exposed missing connection options and the old HTTP POST.
  Focused adapter/request lane: 13 tests, zero failures, seed 475978.
- STT event audit found missing `keepalive_interval_ms` config echo. Added a
  failing contract test, then echo null when disabled or the configured value.
- Independent Go/Elixir live lane: four Call Engine tests and two Console room
  tests pass, seed 784467. Covers PCM at 8/16/24/48 kHz, repeated recognition/
  reply, blocked output interruption and replacement. Local Go origin only.
- Shared live-runner state was owned by another branch. Used an isolated
  temporary runner state and synthetic origin-only environment file; preserved
  the other owner's reservation and did not access provider credentials.
- Load client now exercises incremental TTS WebSockets, adds optional realtime
  input pacing and counts overlapping upgraded client sessions. Its red test
  rejected HTTP fallback before implementation; focused tests pass.
- Root format check caught a trailing comma in the changed origin test; corrected
  before restarting the required gates. Lean verification passed.

- Persisted origin switch/TLS rejection/outage lane passed: one test, seed
  319164. Initial attempt could not find Go from the Vxpipe tool environment;
  prepending the installed Go binary directory resolved the fixture build.
- Go format, vet, full and race suites pass. Local smoke covers HTTP and both
  WebSockets. Paced two-client checks passed: STT duration 2.465 seconds for
  2.46 seconds of audio; TTS first audio preceded its final text fragment.
- Desktop (1280 px) and mobile (390 px) rendered documentation checked in Chrome:
  Inter prose, fenced monospace examples, no page overflow; long URLs scroll
  within code blocks. Public reference documents both realtime directions.
- Go implementation committed/pushed as `49c901f`; Railway deployment
  `712f7600-239d-4e3d-8712-7574c7f26fcf` succeeded at that revision. Public
  HTTP and both realtime smoke checks passed. Live browser inspection confirmed
  the documentation and literal curl upload example through Cloudflare.
- Paced hosted load: STT 8/32/64 clients completed 32/128/256 operations;
  TTS 4/8 clients completed 48/92 operations. No errors or rejections in those
  stages. Above-limit STT 65 clients produced 256 successes/27 HTTP 429s;
  TTS nine clients produced 93 successes/18 HTTP 429s. No other errors, and peak
  sockets stayed at 64/eight. All post-stage speech smoke checks passed.
  Each stage used a ten-second launch window and SOS, not an hour-long or mixed
  soak. Complete latency and environment results are in Go docs/load-test.md.
- User follow-up: replace generic homepage contents with four prominent service
  descriptions and make curl examples independent of shell variables. Desktop/
  mobile checks and focused documentation tests pass; committed in Go `e3027f9`.
- User also requested downloadable binaries and test-gated GitHub releases.
  Following ircxd semantic bump/tag scripts with a VERSION file and an optional
  dry run from topics.club. Go CLI serves with explicit host/port flags. Six
  target archives and checksums are being verified before first publication.
  The referenced wakewords checkout was not present. A local build lacked zip;
  use Python's standard-library zipfile, already needed by version-script tests.

## Final verification

- All Vxpipe root gates pass: format, compile with warnings as errors, strict
  Credo, unused-lock check and the full suite (3,841 tests, zero failures,
  150 excluded, seed 317409). Lean verification also passed.
- Go full/race/vet and three isolated release-script tests pass. All six binary
  targets build; archive checksums and Windows archive contents verify. Extracted
  Linux binary reports 0.1.0 and passes HTTP plus realtime smoke. Container
  verification caught VERSION missing from its allowlisted build context; added
  it before repeating the image check.

## Remaining acceptance

Vxpipe commit/push and final Go release/deployment verification are pending.
