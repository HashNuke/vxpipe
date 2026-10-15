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

- Both repositories pushed: Vxpipe `975cf133`, Go `8cd8d57`. Final homepage/CLI
  deployment `4adf0dd3-ead8-43cd-8ab7-d2aa35b0bc08` succeeded at Go `8cd8d57`.
  Live browser and HTTP/realtime smoke passed. Vxpipe hosted interoperability and
  configured-room checks passed too: four plus two tests, seed 297800.
- GitHub Actions completed both test and release jobs for v0.1.0, publishing six
  binary archives and checksums. User then requested a built-in loadtest command
  with sustained 60/90-second session checks. A follow-up patch release reuses
  the Go load client and holds one original socket per worker across turns;
  it does not replace failed sessions. The new repeated-turn test caught a
  writer-cancellation race hidden by single-turn connections; joining a successful
  writer before canceling its context fixed it. Race tests now pass.

- Built-in CLI committed/pushed in Go `f9b1887` and tagged v0.1.1. It accepts
  tts/stt/realtime-tts/realtime-stt, concurrency, duration, turn timeout, text,
  pacing and optional reconnect mode. Default realtime mode holds original
  sockets. Local binary checks exercised all four services and the stt alias;
  full/race/vet and version-script tests passed.
- Sustained hosted STT: 64 original sessions, all successful, 2,238 validated
  turns, minimum successful session 90.0448 seconds, zero errors and 429s.
  Post-run HTTP/realtime smoke passed. TTS then held eight original sessions
  successfully for at least 90.2505 seconds, completing 1,739 validated turns
  with zero errors and 429s. These were separate workloads.

## Follow-up release and capacity work

- GitHub v0.1.1 and v0.1.2 test/release jobs succeeded. Go `8533195` adds
  startup-validated admission settings (defaults eight TTS / 64 STT; maximum
  1,000), matching client capacity, and the requested development-workflow note
  shared by the homepage and llms.txt. Desktop/mobile rendered checks passed.
  Config and admission tests failed before implementation, then passed; full
  race/vet and release-script checks passed.
- Railway deployment `574acb44-5fce-4fca-b4f8-f8e692e5d54c` succeeded at
  `8533195`. All speech smoke checks passed. For the user-requested binary
  capacity search only, both admission limits were set to 1,000 while keeping
  0.5 vCPU / 125 MB. Original capacity environment variables were absent and
  will be removed again after the search.

- The 90-second exploratory search at Go `8533195` passed STT at 298,
  415, 473 and 502 clients; 532 and 1,000 lost sessions and the process
  restarted. Readiness recovered. TTS passed 1,000 original sessions for
  at least 90.296 seconds, 40,233 turns, with zero failures.
- User refined the search to 30-second holds, increasing by 1,000 on success
  before binary narrowing. Go `7bfdace` removes the artificial 1,000-client
  ceiling; positive operator-configured limits still bound admission. Existing
  config tests demonstrated the old rejection at 2,000 before the change; full
  race/vet and release-script checks passed afterwards.
- Go `f3e832d` makes the self-hosting repository a labeled HTML link while
  preserving the plain URL for agents. Desktop/mobile Chrome inspection passed.
  Reviewed every Go/Python test file in morsecode-audio and removed three
  brittle presentation tests, unused-route assertions and duplicate API-key
  cases. Retained the Cache-Control regression for the observed Cloudflare
  rewrite, plus protocol, Morse, admission, cancellation and release checks.
  No link-markup unit test was retained, per user preference.
- Both commits are pushed and v0.1.3 tagged. The new capacity experiment uses
  temporary admission of 10,000 per direction, unchanged 0.5 vCPU / 125 MB.

- v0.1.3 test and release jobs succeeded. Downloaded the published Linux AMD64
  artifact, verified SHA-256 and version output. The earlier v0.1.2 published
  binary also passed local HTTP and both realtime smokes/load commands.
- Final 30-second search targeted morsecode.vxpipe.com at Go `7bfdace`,
  separately per service. STT failed at 1,000/750/625/562; 500 passed, then
  531 passed twice (minimum holds 31.562/31.564 seconds; repeat first-partial
  p95 1.814 seconds). Four overload failures exhausted automatic restarts;
  Railway reported CRASHED. Redeployed the same revision as
  `929538b5-962c-46f6-8349-39ea0da73447`, observed SUCCESS and resumed at 531.
- TTS passed 1,000, failed 2,000 (one error), passed 1,500/1,750, failed 1,875
  (65 errors), passed 1,812, failed 1,843 (20 errors), then passed 1,812 again.
  The repeat completed 19,729 turns, minimum hold 30.285 seconds, p95 first
  audio 5.540 seconds. No TTS process restart appeared in runtime logs.
  Neither search saw HTTP 429s. These are zero-error results with a ten-second
  handshake/turn deadline, not a low-latency promise or deterministic maximum.
  Each original socket held for at least 30 seconds, with staggered startup.
- Go `4b481fa` commits the complete stage tables, failed-stage recovery, workload,
  latency and measurement limitations to docs/load-test.md; pushed main.
  HTTP and both realtime smoke checks passed after the searches.
- Removed the two temporary Railway admission variables, returning to default
  eight TTS / 64 STT caps. Read-back confirmed both variables absent. Final
  deployment `1bb57118-af41-4022-b880-8643514cdfc3` succeeded at `4b481fa`.
  All speech smoke checks passed. Nine TTS clients produced eight successes /
  one HTTP 429; 65 STT clients produced 64 successes / one HTTP 429, with zero
  other errors. The final Go main CI run also passed.
- The user confirmed the selected failure criteria: any error, disconnect or
  operation exceeding ten seconds, with response latency reported separately.
  Both repeated passing counts meet those criteria. No acceptance remains open.
