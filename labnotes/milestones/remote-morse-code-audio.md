# Hosted Morse audio provider

Status: original implementation and local Railway preparation complete, 2026-10-15.
The baseline below records its original acceptance scope. Subsequent public
hosting uses `https://morsecode.vxpipe.com` without authentication. The user has
now requested WebSocket TTS; its changed contract and acceptance are tracked in
[Realtime Morse synthesis](realtime-morse-synthesis.md). See the updated
[design](../../docs/remote-morse-code-audio.md) for current behavior.
Scope simplified at the user's request. This replaces the earlier goal of
complete ElevenLabs speech API parity: the service performs existing Morse TTS/STT operations over
the network, using the relevant ElevenLabs request and response conventions.

## Outcome and boundaries

- A standalone Go service in `~/projects/morsecode-audio`, with remote
  `https://github.com/HashNuke/morsecode-audio`.
- One Vxpipe provider, `Vxpipe.Providers.MorseCodeApi`, ID `morse_code_api`.
  Follow existing adapter conventions: `TTS`, `TTSSession`, `STT` and
  `STTSession` under that namespace. The suggested concatenated TTS/STT names
  are examples, not required class names or product labels.
- Text becomes the same Morse PCM as the local provider. Morse PCM becomes
  text with the same alphabet, normalization and timing. No human-speech model.
- ElevenLabs-shaped HTTP TTS and realtime STT are the integration boundary.
  Do not reproduce ElevenLabs' whole speech platform or its model semantics.
- Accept any nonempty compatibility API key in `xi-api-key`; no registration,
  validation service, account system, token issuance or key database.
- No persistent storage, retained audio/transcripts, job system or uploads
  directory. Active requests and decoder sessions use bounded process memory.
- The user deploys to Railway at `https://morse-audio.definerun.com`.
  Prepare and verify the deployment package locally; actual hosted verification
  follows the user's deployment.

The earlier Go implementation contained more API features than this requires.
Those features and their dependencies have been removed.
Compressed format matrices, timestamp alignment APIs, TTS WebSockets,
multi-context synthesis, browser tokens, discovery pagination, voice settings,
URL ingestion, diarization, webhooks and retained jobs are outside this scope.
Historical completion evidence for those features is not a reason to keep them
as requirements. Do not add a new abstraction or compatibility framework.

## Sources and prerequisites

- [Design decision](../../docs/remote-morse-code-audio.md).
- [Local Morse providers](morse-code-audio-providers.md).
- [Provider integration packages](provider-integration-packages.md).
- [Tenant provider credentials](tenant-provider-credentials-and-platform-configuration.md).
- [Speech contract](../../docs/speech-provider-contract.md) and
  [session ownership](../../docs/speech-session-ownership.md).

The existing room lifecycle, permission system and provider supervision remain
the owners of their behavior. Add focused evidence for the new network boundary;
do not create a second speech state machine or another room framework.

## Required contract

| Operation | Interface | Morse behavior |
| --- | --- | --- |
| TTS | `POST /v1/text-to-speech/{voice_id}` and `/stream`, JSON `text`/`model_id` | Raw mono S16LE PCM; `output_format=pcm_16000` for the normal room path, with the local provider's 8/16/24/48 kHz PCM rates where selected |
| Batch STT | `POST /v1/speech-to-text`, multipart PCM/WAV | Small direct round-trip/debugging interface; transcript from Morse tones |
| Realtime STT | `GET /v1/speech-to-text/realtime` WebSocket | Session acknowledgement, base64 PCM chunks, partial/committed transcripts and errors; Vxpipe uses mono 16 kHz |
| Discovery/probe | `GET /v1/models`, `GET /v1/voices` | Fixed Morse model/voice catalog sufficient for service setup |
| Authentication | `xi-api-key` on speech/discovery requests | Any nonempty representable key; missing key gets an auth error |
| Health | `GET /healthz`, `GET /readyz` | Unauthenticated local checks; readiness becomes false during shutdown |

The explicit PCM profile takes precedence over ElevenLabs' MP3 default.
Document the supported subset accurately; invalid PCM formats and unsupported
JSON/WS fields fail clearly. Do not claim arbitrary ElevenLabs SDK calls work
unchanged.

Streaming is required in both directions. TTS renders and flushes PCM chunks
before the full audio is generated; Vxpipe starts consuming them immediately.
Realtime STT accepts continuous PCM chunks and emits partial/final text. Preserve
backpressure and cancellation. The batch upload route is only a file/debugging
convenience and must not replace the streaming room path.

Match the local Morse defaults: 700 Hz tone, 60 ms dot, amplitude 4096,
1/3-unit marks, 1/3/7-unit gaps and a 14-unit utterance tail. Realtime recognition
must not split a word gap into a completed turn. Use transcript onset for Morse;
human-speech VAD is not required. Independent Elixir/Go audio fixtures establish
interoperability without requiring byte-identical floating-point waveforms.

## Endpoint configuration and development

`MORSE_CODE_API_BASE_URL` belongs to Vxpipe and is read in
`config/runtime.exs`. One origin supplies discovery, credential probes, TTS
and STT. Derive WS/WSS from HTTP/HTTPS; do not store the URL in credentials or
published call specs. Keep the existing private origin validation and normal
TLS verification.

| Setting | Local Go development | Railway / hosted use |
| --- | --- | --- |
| Go `HOST` | `127.0.0.1` | `0.0.0.0` |
| Go `PORT` | `8787` or another free port | Railway's injected value |
| Vxpipe `MORSE_CODE_API_BASE_URL` | `http://127.0.0.1:8787` | `https://morse-audio.definerun.com` or the generated HTTPS domain |

Run Go independently, then start Vxpipe with the matching origin. A containerized
Vxpipe needs a reachable host/container address rather than its own loopback.
An unused provider must not prevent Vxpipe startup; selecting it without the
required runtime configuration should fail clearly. Never fall back to another
host when the configured origin is unavailable.

After deployment, drain calls, change the Vxpipe variable and restart it.
Keep the same service credential and published call spec. Rollback restores the
previous origin and restarts Vxpipe. Local development remains available after
the hosted endpoint is introduced.

## Checkpoints

### A — Small standalone Morse API

The codec, HTTP and realtime speech paths implement the required contract above.

- [x] Implement the Go Morse encoder/decoder and independent interoperability fixtures.
- [x] Implement authenticated PCM TTS, batch PCM/WAV STT and realtime STT.
- [x] Bound request sizes, streaming buffers and shutdown; keep processing in memory.
- [x] Remove unnecessary TTS WS/context/token/format machinery and its deployment
  dependencies. Retain only code needed by the required speech paths.
- [x] Reduce documentation, smoke commands and CI to the supported contract;
  remove claims that full ElevenLabs feature parity remains a future gate.
- [x] Verify the simplified server's normal round trip, invalid input, arbitrary
  keys, missing keys, chunk boundaries and disconnect cleanup.

Acceptance: a clean standalone checkout produces/recognizes Morse through the
listed interfaces without an external codec service, database or paid provider.

Simplification evidence: Go revision `1d815f5` removes unused protocols,
FFmpeg, token storage, schema inventories and the separate Railway SDK module.
The application has one WebSocket dependency and ships as a static nonroot
binary. Vet and the 35-test/subtest race lane pass. A focused test proves an
early flush for a nearly five-minute synthesis; disconnect/slow-reader checks
still pass. The local production image passes the HTTP/WS smoke command.

### B — One ordinary Vxpipe provider

- [x] Register one `morse_code_api` provider with credential, TTS and STT capabilities.
- [x] Use the existing encrypted service configuration, catalogs and session ownership.
- [x] Resolve one configurable origin for all operations; derive socket schemes.
- [x] Add Console service and model selection using normal adapter conventions.
- [x] Verify saved credentials/publications survive endpoint switching and restart.

Evidence: focused selection/catalog, service and session checks pass. Existing
configured-room tests exercise real Go output and repeated recognition/reply
turns. The full STT integration umbrella run passed 3,841 tests with zero failures
(seed 180080). See the [STT integration note](../20261015-0019-morse-stt-integration.md)
and [restart/TLS note](../20261015-0036-morse-origin-restart.md).
This historical run does not replace checks after subsequent code changes.

Acceptance: a configured room uses the Go service through the ordinary provider
path; local Morse and real ElevenLabs remain separate existing providers.

### C — Focused end-to-end acceptance

- [x] Independently generate Morse input, receive a remote transcript, generate a
  deterministic reply and independently decode remote TTS output.
- [x] Repeat utterances with distinct room turn identities.
- [x] Interrupt/replace blocked remote TTS output through the ordinary room API.
- [x] Inspect Console service/model selection at desktop and mobile sizes.
- [x] Finish the real service-outage check and relevant regression gates.
- [x] Re-run the required local speech round trip against the simplified Go binary.

Use existing room policy tests for the policy engine. Retain focused failure and
cancellation coverage for remote speech; no new policy test framework, browser
microphone path or full platform conformance suite is required.
The current room fixtures use embedded PCM input/output, not browser WebRTC.

Acceptance: the network boundary works, fails clearly and retires owned work
without a fabricated final transcript or stale reply.

Acceptance against Go `1d815f5`: the persisted origin/TLS/rollback and outage
test passes (seed 582279); both repeated round-trip and blocked-output room
cases pass (seed 141071). Root regression passes 3,841 tests, zero failures and
148 exclusions (seed 899255). See the
[network boundary evidence](../20261015-0049-morse-room-boundaries.md).

### D — Railway deployment package

- [x] Build a small standalone production image with an exec-form entrypoint,
  nonroot runtime and no unnecessary codec packages.
- [x] Honor `HOST`/`PORT`, serve HTTP and STT WS on one listener, and provide
  health/readiness plus bounded SIGTERM cleanup.
- [x] Document Railway service settings in one short runbook: repository connection,
  build settings, runtime variables, readiness, generated domain, custom domain,
  TLS/WSS verification and rollback. No volume or database.
- [x] Run one base-URL-parameterized smoke command against the local production
  image, including PCM round trip, realtime recognition and shutdown.
- [x] Record the verified Go/Vxpipe revisions, image and local outcome; leave
  hosted verification explicitly pending until deployment actually occurs.

The runbook must distinguish Go's Railway variables from Vxpipe's outbound URL.
Railway [detects a root Dockerfile](https://docs.railway.com/builds/dockerfiles);
its [deployment healthcheck](https://docs.railway.com/deployments/healthchecks)
uses the listening port. Do not describe readiness as continuous monitoring.

Acceptance: the user can deploy the separate repository without additional
application development, then switch Vxpipe through runtime configuration.

Local package evidence: the scratch image is 2,895,429 bytes, runs as
`65532:65532`, and passed smoke with a read-only filesystem, a 512-MiB limit
and a nondefault injected port. SIGTERM exited 0. The Go repository's
`docs/verification.md` records the image digest; `cmd/smoke -base-url ORIGIN`
is the single local/hosted check. Deployment uses Railway's Dockerfile detection
and documented UI settings, without an additional infrastructure module.

### E — Finish and publish

- [x] Go formatting, vet, unit/integration tests and race checks pass.
- [x] Vxpipe root formatting, warnings-as-errors compile, strict Credo, tests and
  unused dependency checks pass. Run Lean if speech state-machine code changes.
- [x] Relevant Console changes have focused tests and rendered verification.
- [x] Keep labnotes, this checklist and the milestone index accurate.
- [x] Commit small coherent checkpoints in each repository; push Vxpipe when
  implementation and local deployment preparation are complete.

Hosted acceptance is a follow-up after the user's deployment, not a dependency
for preparing the application. Never label localhost evidence as a hosted pass.

Published: Go `main` at `1d815f5`; Vxpipe `morsecode-api` includes acceptance
commit `7c9b8a4e` and deployment handoff `7e1deffc`. Both remote branches were
pushed successfully. This completion update only records the verified status.

## Scope review

The user's 2026-10-15 clarification replaces the original broad API-parity
interpretation and makes adapter naming conventional rather than fixed.
This review removes unneeded requirements; it does not mark removed features as
implemented or claim that pending simplification has already happened.
See the [scope note](../20261015-0057-morse-scope-simplification.md).
