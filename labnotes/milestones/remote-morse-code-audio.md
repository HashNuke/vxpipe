# Morse-code API service and providers

Status: implementation in progress, 2026-10-15. **6 of 9
implementation checkpoints complete (A–F).** The user requested planning first and
clarified the scope as complete ElevenLabs **TTS/STT** compatibility, including
HTTP, streaming, WebSockets, discovery and authentication. Other ElevenLabs
product APIs are outside this milestone. The Go server/catalog, HTTP TTS
formats/streaming, PCM batch STT, realtime STT and both TTS WebSockets are
implemented, and Vxpipe TTS has configured-room acceptance. Full semantic
compatibility, Vxpipe STT and final deployment acceptance remain pending.

## Runnable outcome

A standalone Go project, `~/projects/morsecode-audio`, first serves Morse synthesis
and recognition locally. The user later deploys the prepared application to Railway
at `https://morse-audio.definerun.com`; Vxpipe switches through runtime configuration.
It accepts
any nonempty caller-chosen API key through the ElevenLabs authentication interface.
It has no database, retained audio, stored transcripts or persistent job queue.

Vxpipe exposes **MorseCodeApiTTS** and **MorseCodeApiSTT** through one
`morse_code_api` provider. An ordinary configured room sends real PCM over HTTP/WS
to the service, receives transcripts/audio, handles interruption and replacement,
and finishes without contacting ElevenLabs. Recognition decodes supported Morse
tones; it does not recognize human speech. Existing local Morse and ElevenLabs
selections remain separately usable.

## Prerequisites and design sources

Read these implemented prerequisites before implementation:

- [Local Morse providers](morse-code-audio-providers.md).
- [Simpler speech integrations](simpler-speech-integrations.md).
- [Provider integration packages](provider-integration-packages.md).
- [Tenant provider credentials](tenant-provider-credentials-and-platform-configuration.md).
- [Provider expansion and live acceptance](provider-expansion-and-ai-gateway.md).
- [Transcript start and optional VAD](transcript-start-and-optional-vad.md).
- [Call spec editor](call-spec-editor.md), for selectable Console services and models.

The architecture and external reference links live in the companion
[Morse-code API design](../../docs/remote-morse-code-audio.md). Also read the
[speech contract](../../docs/speech-provider-contract.md),
[scoped ownership](../../docs/speech-session-ownership.md),
[provider packaging](../../docs/provider-integration-packages.md),
[ElevenLabs STT session](../../docs/elevenlabs-stt-session.md), and
[speech-start contract](../../docs/stt-speech-start-detection.md).

This slice does not depend on unfinished STS, AI gateway, onboarding, packaging
or retention work. It does not release the Vxpipe delivery review hold.

## Approved requirements and proposed contracts

User-approved requirements are Go, a separate project, the named Railway host,
no persistence, arbitrary compatibility keys, complete TTS/STT API coverage,
and two named Vxpipe speech capabilities. The user additionally requires a temporary
development endpoint override, local Go-server testing before hosted deployment,
and a Railway-ready application they can deploy themselves. The concrete defaults below are design
proposals to validate in checkpoint A; they are not claims of existing behavior.

### API compatibility ledger

Maintain `docs/elevenlabs-compatibility.md` in the Go project. Pin the reviewed
upstream API/schema revision and SDK versions. For every speech endpoint, field,
format, default, response, error and WS message, record its fixture, test and
status: implemented, intentionally different for Morse/no retention, or blocked.
An endpoint existing is insufficient evidence of full compatibility.

| Surface | Required routes / behavior | Checkpoint |
| --- | --- | --- |
| HTTP TTS | `POST /v1/text-to-speech/{voice_id}` and `/stream`; binary audio, correct content type, output-format selection and defaults | B, C |
| Timed TTS | Same prefix with `/with-timestamps` and `/stream/with-timestamps`; base64 audio, original/normalized alignment and correct stream framing | C |
| TTS WebSockets | `GET /v1/text-to-speech/{voice_id}/stream-input` and `/multi-stream-input`; initialization, incremental text, flush, context lifecycle, audio/alignment and final events | E |
| Batch STT | `POST /v1/speech-to-text`; multipart input, transcript, timestamp and multichannel response variants | B, H |
| Realtime STT | `GET /v1/speech-to-text/realtime`; session acknowledgement, audio chunks, partials, commits, timestamps, keepalive and errors | D |
| Discovery | `GET /v1/models`, `/v1/voices`, `/v2/voices`, `/v1/voices/{voice_id}`, and applicable read-only voice-settings routes; stable synthetic Morse catalog and pagination | A, H |
| Authentication | `xi-api-key`, documented TTS initialization `xi_api_key`, applicable bearer mechanisms and token query fields; `POST /v1/single-use-token/{token_type}` for speech token types | A, E, H |
| Retention-dependent speech features | Inventory transcript retrieval/deletion, asynchronous webhook jobs and request-ID stitching; resolve their conflict with no retention explicitly | A, H |

Match SDK-facing paths, field casing, null/omitted values, content types, status
codes and event ordering against pinned fixtures. Do not assume HTTP timing
streams are SSE or that a TTS final marker has the same casing across interfaces.
Test both success and failure decoding through official clients where supported.

Full speech compatibility includes the documented MP3 default and all advertised
codec/rate combinations, not just Vxpipe's PCM path. Inventory PCM, WAV, MP3,
mu-law, A-law, Opus and other values in the pinned schema. Implement required
encoders/decoders or retain a visible compatibility blocker; never return PCM
under another codec label. Account for codec delay in alignment.

Morse has no natural-language voice similarity, accent or probabilistic speaker
recognition. Specify field-by-field mappings for model IDs, voice settings,
normalization, language, diarization, audio-event tags and newer semantic options.
Safe compatibility no-ops must be documented; a requested transformation with no
implementation must fail explicitly. No fabricated confidence or AI result.

### Authentication and storage

- Any nonempty representable API-key string is accepted without registration,
  lookup, account creation or an outbound ElevenLabs check. Missing/empty keys
  follow pinned auth-error fixtures. Specify precedence when several auth forms
  are supplied; only documented initial WS auth may precede authentication.
- Keys confer no access-control boundary in this service. Preserve their privacy
  in logs and Vxpipe credential storage anyway; use synthetic keys in examples.
- A compatibility token can use bounded, expiring process memory for issuance
  and single-use consumption. Proposed first deployment: one replica, token
  expiry matching the pinned API, atomic consumption and restart invalidation.
  No Redis or database. Document that cross-replica single-use semantics need a
  different design before scaling; a signed stateless token alone cannot enforce
  one-time use. This transient protocol state is not retained user content.
- HTTP bodies, PCM, text, decoder state and WS contexts exist only for active
  bounded work. No multipart spill files, recording, transcript cache, disk
  transcoding or durable background work. Immutable catalog/fixtures in the
  binary or source repository are allowed.
- `enable_logging` never enables content retention. Retained transcript APIs,
  durable asynchronous completion and previous-request lookup cannot have full
  ElevenLabs semantics under this requirement. A must propose exact explicit
  errors/zero-retention semantics; H cannot claim unrestricted compatibility
  until the owner accepts those exceptions. Do not silently narrow the goal.

### Morse and audio

- Start with the existing alphabet and normalization: uppercase, collapsed word
  whitespace, supported A–Z/digits/punctuation; unsupported characters fail before
  synthesis begins where the complete request is available.
- Initial interoperable profile: mono S16LE PCM, 16 kHz, 700 Hz tone, 60 ms dot,
  amplitude 4096, 1/3-unit marks and 1/3/7-unit gaps. Existing local Morse adds a
  14-unit utterance tail. Preserve and test that profile before adding tunable
  synthetic voices, speeds or other sample rates.
- Carry partial sample bytes, detection windows and incomplete marks across
  arbitrary chunks. Finalization must flush the final character/word once;
  silence does not create text. Reject malformed or undecodable signals with
  bounded outcomes. Derive timestamps from sample positions.
- Realtime auto-commit must distinguish Morse inter-element, letter, word and
  utterance silence. A 7-unit word gap must not accidentally finalize a turn.
  Test slow-speed voices against the configured commit threshold.
- No local Silero speech-onset guarantee for pure tones. The Vxpipe default uses
  transcript onset; document/validate `vad` support instead of inheriting a human
  speech detector accidentally. Provider commits remain segment evidence, not
  automatically proof of a completed human turn.

### Vxpipe ownership and configuration

- Manifest: `Vxpipe.Providers.MorseCodeApi` in `vxpipe_providers`, with
  credential, STT and TTS capabilities only; provider ID `morse_code_api`.
- Sessions: `MorseCodeApi.STTSession` and `MorseCodeApi.TTSSession` under
  `apps/vxpipe_call_engine/lib/vxpipe/providers/morse_code_api/`. Keep sockets,
  request workers, credit, cancellation and readiness in the existing speech
  allocation subtree. No global speech queue or new call state machine.
- Use the ordinary encrypted API-key credential and tenant/platform service
  resolution. Console labels identify compatibility-only keys and Morse audio.
  Tests proving remote reachability must not claim key ownership validation.
- Temporary development setting: `MORSE_CODE_API_BASE_URL`, read only in
  `config/runtime.exs`. Default to `http://127.0.0.1:8787` in development; tests
  inject an ephemeral local origin. Until hosted cutover, require an explicit
  origin when this provider is selected outside development/test. An unused
  provider must not prevent ordinary Vxpipe startup. Do not default to an
  undeployed host or silently fall back between local and hosted services.
- One validated HTTP(S) origin governs TTS, STT, discovery and credential probes.
  Derive WS/WSS by replacing the scheme and append API paths exactly once.
  Accept a trailing slash; reject userinfo, query/fragment, non-root paths and
  unsupported schemes. Permit HTTP for explicitly configured local development,
  including container networking; hosted deployments use verified HTTPS/WSS.
  No public call-spec URL override; never forward keys on redirects.
- Pass the resolved origin privately through configuration and session startup;
  do not bake it into compiled plans, stored call specs or credentials. Changing
  the variable and restarting Vxpipe redirects new sessions without rebuilding
  code, reissuing keys or republishing call specs. Existing sessions are not
  migrated midstream; drain active calls before the planned restart.
- Reuse ElevenLabs protocol code only behind a focused internal boundary.
  Existing constructors reject endpoint overrides, and current runtime/catalog
  dispatch explicitly names providers; changing just a URL will not integrate
  this provider. Preserve ElevenLabs defaults and error behavior with regressions.
- Add model/voice catalog, compiled selection, startup, readiness, usage and
  editor support together. Count submitted text/audio truthfully; absence of an
  upstream charge is not a provider-reported price. No STS advertisement.

### Local-first workflow and endpoint cutover

Deliver this in four stages, using the existing checkpoints below rather than
creating a second implementation checklist:

| Stage | Owning checkpoints | Completion evidence |
| --- | --- | --- |
| Local provider development | A–G | `MorseCodeApiTTS` and `MorseCodeApiSTT` use the selected local Go origin for discovery, authentication probes and speech; a configured room completes repeated turns. |
| Deployment preparation | H and I preparation | The separate Go repository contains the deployable image, Railway configuration and runbook; the production image passes local protocol, resource and shutdown checks. |
| User deployment | I hosted verification | The user deploys the Go service; generated and custom HTTPS domains pass the same HTTP/WS smoke checks, with the tested revision recorded. |
| Vxpipe switch and rollback | G local rehearsal, I hosted cutover | Changing only the runtime origin and restarting moves new sessions to the selected server; restoring the previous origin also passes with unchanged services and call specs. |

Railway availability is not a dependency for the first two stages. Keep the
endpoint configurable throughout all four stages; a future hosted default must
not remove the ability to run the development workflow without a remote service.

These are the intended commands after implementation, not commands implemented
by this planning checkpoint:

```shell
# In the standalone Go project (choose another free port if necessary).
HOST=127.0.0.1 PORT=8787 go run ./cmd/morsecode-audio

# In Vxpipe; both speech capabilities and service probes use this origin.
MORSE_CODE_API_BASE_URL=http://127.0.0.1:8787 bin/dev

# After the user deploys the Go app: set this in Vxpipe's runtime environment,
# then restart Vxpipe. Railway's generated HTTPS domain also works initially.
MORSE_CODE_API_BASE_URL=https://morse-audio.definerun.com
```

The Go listener's `HOST`/`PORT` and Vxpipe's outbound base URL are separate
settings. If Vxpipe runs in a container, its loopback is not the host Go server:
document a reachable host/container DNS name and matching Go bind address.
Do not replace a developer's selected free port with the example port implicitly.

Configuration handoff:

| Setting | Application that reads it | Local development | Railway / hosted cutover |
| --- | --- | --- | --- |
| `HOST` | Go API | `127.0.0.1` for native development | `0.0.0.0` |
| `PORT` | Go API | `8787`, or another selected free port | Read Railway's injected value |
| `MORSE_CODE_API_BASE_URL` | Vxpipe | `http://127.0.0.1:8787`, matching the chosen listener | Verified `https://morse-audio.definerun.com` or generated Railway HTTPS origin |
| Compatibility API key | Vxpipe credential configuration; sent to Go API | Any nonempty synthetic value | The same value can remain in use; no Go-side key registration |

The deployment runbook must distinguish the Go service's Railway variables from
Vxpipe's runtime variables. Setting `MORSE_CODE_API_BASE_URL` only on the Go
service does not configure Vxpipe. Include a readiness request and authenticated
discovery request against the selected origin before enabling speech services.

Keep the override through local testing, user deployment and hosted verification.
Any later removal of the development override or adoption of a hosted default
is a separate recorded follow-up after successful cutover, not part of this
milestone's automatic cleanup. Rollback restores the previous origin and restarts
Vxpipe; it does not modify call specs or credentials.

Endpoint and deployment acceptance must cover this matrix:

| Environment | Go listener | Vxpipe origin | Required evidence |
| --- | --- | --- | --- |
| Native development | Loopback and selected free port | Explicit matching HTTP origin | Discovery, probe, HTTP TTS and WS STT all reach that process |
| Container development | Reachable container interface and injected port | Reachable host/container DNS origin | No accidental use of the container's own loopback |
| Local TLS fixture | Test HTTPS listener | HTTPS origin | HTTPS/WSS derivation and certificate validation |
| Railway | `0.0.0.0:$PORT` | Generated or custom HTTPS origin | Public readiness, streaming, WS upgrades and bounded drain |
| Cutover/rollback | New/previous verified listener | Change runtime variable and restart | Same saved service, credentials and call spec; all new traffic uses selected origin |

If the selected origin is unavailable, report service unavailability and recover
through ordinary lifecycle handling. Do not send a request or key to a fallback
origin. Test this both before and after switching between two local servers.

The handoff must include a repeatable smoke command that accepts an explicit
base URL and a synthetic compatibility key. Run it first against the selected
local port, then against Railway's generated HTTPS domain, and finally against
the custom domain. It must check readiness, authenticated discovery, a TTS/STT
round trip and streaming/WS completion with bounded deadlines. Keep credentials
out of its output. Record the tested origin and application revision so a local
pass cannot be mistaken for hosted acceptance.

## Checkpoints

Each checkpoint leaves a runnable slice. Write and run the smallest externally
observable failing test first, implement to green, then refactor with relevant
regressions green. Keep implementation, fixtures, documentation and evidence
together. Commit only when the user requests commits.

### A — Runnable server, catalog and compatibility contract

Dependencies: prerequisites above; no Go project assumed to exist.

- [x] Inspect the sibling project's instructions/status before creating or editing
  it. Initialize a standalone Go module, pinned toolchain, `cmd/morsecode-audio`,
  focused internal packages and CI; no Vxpipe runtime dependency.
- [x] Freeze the speech API ledger from official reference/schema and clients,
  including every format, auth location, default, error and retention conflict.
  Record accepted exceptions separately from implemented parity.
- [x] Write failing HTTP tests, then add `net/http` startup, `/healthz`, `/readyz`,
  nonempty-key acceptance, missing-key rejection and static Morse discovery.
  Select a maintained WS library before D; avoid implementing RFC framing.
- [x] Bind loopback locally and `0.0.0.0:$PORT` on Railway; configure shutdown,
  request limits and content-free diagnostics. Reserve 8787 only if available.
- [x] Document and validate Go `HOST` and `PORT` independently of Vxpipe's URL.
  Provide a local environment example and run command; reject invalid ports,
  report bind conflicts clearly, and do not require Railway credentials locally.
- [x] Smoke with two different synthetic keys and no key. Catalog IDs must be
  usable by subsequent endpoints; health probes require no compatibility key.

Evidence: the Go repository now has a runnable server, pinned Go 1.26.1, CI,
HTTP schema snapshot and field inventory. Initial package tests failed before
implementation; focused tests, vet and race checks now pass. The pinned ElevenLabs
Python SDK 2.72.0 reads discovery and six responses validate against the captured
schema. A real binary served a nondefault local port and shut down on SIGTERM.
All three WS AsyncAPI contracts (61 schemas) are now pinned with source digests;
HTTP/WS snapshot hashes and references validate. Selected coder/websocket for D.
The ledger proposes exact no-retention errors; their owner acceptance remains a
separate H gate, and no unimplemented API feature is marked complete.
See [implementation evidence](../20261014-2120-implement-morse-api.md).

Exit: a clean checkout starts locally and official-client discovery plus auth
fixtures pass. Missing scope decisions stay recorded; writing the ledger does
not mark API features implemented.

### B — HTTP synthesis-to-transcription round trip

Dependencies: A.

- [x] Add independent known-tone and sample-run fixtures before Go codec code.
  Match the existing local Morse default and reference alphabet/timing.
- [x] Implement bounded incremental synthesis/detection behind transport-free
  Go APIs; test normalization, final tail, unsupported text, silence, incomplete
  signals, odd bytes and randomized chunk boundaries.
- [x] Add authenticated HTTP TTS with explicit `output_format=pcm_16000` and
  synchronous multipart WAV/PCM STT. This is an intermediate profile until C/H;
  do not claim default-format/full compatibility yet.
- [x] Stream multipart parts without temporary files; bound encoded input,
  decoded audio duration, text and generated output before expensive allocation.
- [x] Prove Go TTS → local Elixir STT and local Elixir TTS → Go STT, in addition
  to independent fixture checks. Keep cross-repository checks explicitly tagged.

Evidence: independent square-wave fixtures pass at seven PCM rates with arbitrary
byte boundaries. Tone/space ratios, normalization, malformed signal failures,
manual/automatic finalization and sample-derived timestamps pass. Go race/vet
checks and the official SDK PCM round trip plus response-schema validation pass.
CallEngine's tagged interoperability lane passes Go synthesis → Elixir decoding
at four rates and Elixir synthesis → Go transcription. HTTP uploads use bounded
memory without temporary files. See implementation labnotes for initial failures
and corrections. This checkpoint does not claim MP3 defaults or streaming APIs.

Exit: a CLI request generates `SOS TEST 123`, its audio decodes correctly through
the HTTP STT endpoint, and invalid/silent input never invents a transcript.

### C — HTTP streaming, formats and alignment

Dependencies: B.

- [x] Add red tests for first-chunk delivery, timed response framing, client
  cancellation, output limits and slow readers before implementing streams.
- [x] Implement both binary and timestamped TTS variants. Preserve word gaps
  and sample-derived character timing through text normalization/chunking.
- [x] Implement the pinned default MP3 response and complete the TTS output
  format matrix. Prefer existing codec libraries; if a subprocess is necessary,
  use bounded pipes, cancellation and image-pinned codecs with no temp files.
- [x] Maintain bounded queues, write deadlines and per-request cancellation.
  Distinguish errors before headers from terminal failures after streaming starts.
- [x] Verify actual decodability, duration and MIME types with an independent
  decoder. Verify first bytes arrive before full synthesis completes.

Evidence: all 28 nonstreaming and 21 streaming formats pass independent decode
and packet-clock checks; MP3 is the default. Both timed routes preserve original
and normalized characters with sample-derived timing. Official SDK 2.72.0 consumes
all four routes and both timed schemas validate. An early-output check leaves over
290 seconds of a 300-second input unrendered on cancellation. Real HTTP disconnect
and repeated write-deadline failure tests release owned work; race/vet pass.
FFmpeg uses bounded pipes only. The pinned nonroot image passes all 49 binary
format cases and SDK checks on a read-only filesystem with an injected port and
512 MiB limit; Railway configuration/handoff work has begun in I.
Alignment uses the source PCM clock; MP3 decoders can expose codec priming/padding,
documented in the Go ledger for H's final semantic review. Optional request fields,
WebSockets, provider sessions and hosted behavior remain unchecked.

Exit: HTTP clients consume every TTS response variant, including omitted
`output_format`, and a disconnected slow reader releases all owned work.

### D — Realtime STT session

Dependencies: B; A's auth and schema contracts.

- [x] Write protocol fixture tests before WS handlers: authenticated upgrade,
  `session_started`, `input_audio_chunk`, `partial_transcript`,
  `committed_transcript`, optional timed results and protocol errors.
- [x] Implement supported PCM rates and mu-law input, manual commit, silence
  auto-commit, empty-audio controls and keepalive without fabricated text.
- [x] Verify repeated commits, no-audio commits, split symbols, long segments,
  idle timeout, oversized messages, malformed base64 and disconnect cleanup.
- [x] Define partial stability and timestamp origin across successive commits.
  Preserve isolated decoder state and bounded unread input for each socket.
- [x] Use a raw Scribe-compatible client and Vxpipe's protocol fixture shape to
  decode independent Morse chunks, then start a second turn on the same socket.

Evidence: the first protocol tests failed 404. Independent square-wave E/T
fixtures pass all seven realtime input formats, repeated manual/VAD commits,
split samples, word gaps, empty commits, timed ordering and cumulative sample
offsets. A 500-character segment, separate sockets, malformed/oversized input,
silence keepalives, capacity release, idle/lifetime expiry and drain pass under
the race detector. The 22.05-kHz exact-tail test exposed and verified a fix for
one-window commit quantization. Pinned official SDK 2.72.0 consumes two turns and
every response validates against the captured AsyncAPI. The input/acknowledgement
shape matches Vxpipe's Scribe wire module; provider integration remains F/G.
The read-only container passes realtime/HTTP SDK checks and exits 0 after SIGTERM
with an active STT socket. Optional semantic fields and browser tokens remain H/E.

Exit: an authenticated session recognizes two distinct phrases with exactly one
final publication per committed segment and no state leakage after close.

### E — TTS WebSockets and browser authentication

Dependencies: C, D.

- [x] Implement bounded in-memory token issuance for all three speech purposes
  and token-only batch/realtime STT; prove expiry, atomic consumption, wrong
  purpose/replay rejection, restart invalidation and browser-origin/CORS behavior.
- [x] Build the incremental text-to-PCM planner with independent gap/timing
  fixtures, cumulative text/duration bounds and a single final utterance tail.
  Verify arbitrary text fragments reproduce finite synthesis at every PCM rate.
- [x] Support one continuous codec stream for open-ended text input. Verify all
  21 streaming formats emit audio before input ends, and cancel/join codecs even
  when their input producer is waiting for another fragment.
- [x] Write red single-context fixtures and implement initialization, incremental
  text, flush/end-input, keepalive, original/normalized alignment and final/error
  messages. Verify bounded initialization, header/first-message/token auth,
  browser CORS and cancellation while PCM/MP3 codecs await more input.
- [x] Write red multi-context transcript fixtures before its handler; cover
  initialization, incremental text, flush, close-context/close-socket and errors.
- [x] Implement interleaved context generation with fair bounded output and
  exactly correlated audio/alignment/final messages. Closing one context must
  not close or contaminate another. Preserve Morse gaps across text fragments.
- [x] Implement all speech token types, expiry, atomic single consumption,
  wrong-purpose/reused-token errors and the pinned browser auth transports.
  Redact query strings containing tokens and initialization credentials.
- [x] Bound unauthenticated initialization time; define browser origin/CORS
  policy and OPTIONS handling for the tested SDK flows.
- [x] Test header, first-message and token authentication with official SDK
  flows where supported; test two contexts and abort one during output.

Evidence: all three token types issue through the pinned SDK/schema;
batch and realtime STT consume tokens without keys. Clock-controlled tests cover
15-minute expiry and capacity recovery; 16 concurrent consumers produce exactly
one accepted transcript. Invalid explicit tokens never fall back to supplied keys.
Both TTS routes consume tokens and supports bearer/header/initial-message
credentials. Native Chrome 154 passes cross-origin initial-key/token TTS and
token STT against the read-only container. This is browser API evidence, not
acceptance of every browser SDK. The Go race suite/vet pass. E is complete for its transport/lifecycle scope.
The incremental text planner also passes independent tone/space intervals and
84 fragmentation comparisons across seven rates. Continuous codec output passes
21 early-packet/independent-decode cases and starved-input cleanup. Single-context
PCM reproduces finite synthesis with original/normalized chunk-relative alignment;
repeated flush keeps the connection usable and EOS emits one final then closes.
Pinned Python SDK 2.72.0 passes PCM/default MP3 via a trusted local TLS fixture;
disabling fixture session tickets resolved intermittent pre-upgrade stalls in ten
consecutive Python 3.12/3.13 runs. Hosted TLS remains unverified. The production
image passes active STT/PCM-TTS/MP3-TTS SIGTERM drain with exit 0, no OOM or file
changes. Go commit `601f8cf` contains the single-context slice.

Go commit `b922e71` adds multi-context TTS: the initial tests failed 401/404,
then pass independent output, flush-close preservation, cancellation, immediate
ID reuse, five-context limits, per-context idle refresh and fair ready-output
rotation. Both routes pass all key/bearer/token locations and initialization
limits. SDK 2.72.0 supplies multi-context payload/response types but no high-level
transport client; a raw WS runner validates those types and the pinned AsyncAPI.
Chrome interrupts E after 1,920 bytes, completes T with 32,640 bytes, and sees one
final per context. The production image drains STT plus four active TTS encoders
(single PCM/MP3 and two multi-context MP3), exiting 0 without OOM or file changes.
General HTTP/STT auth remains the documented key/token interface; bearer fields
belong to the TTS bindings. Full optional-field and codec timing semantics remain
H work, and local acceptance does not establish hosted behavior.

Exit: a browser-capable client generates Morse with both WS APIs and consumes
a token once; idle or abandoned sockets release memory and execution workers.

### F — Selectable MorseCodeApiTTS in Vxpipe

Dependencies: C and the implemented provider/service prerequisites.

- [x] Red-test manifest, capability selection, arbitrary synthetic credential,
  model/voice configuration and private runtime endpoint resolution.
- [x] Add the private origin validator and `MORSE_CODE_API_BASE_URL` runtime
  setting: development-local default, explicit hosted configuration, HTTP→WS and
  HTTPS→WSS derivation, trailing-slash normalization and nondefault ports.
  Reject userinfo, query/fragment, non-root paths, invalid ports and schemes.
- [x] Connect the configured origin to discovery/probes and TTS; no hardcoded
  hosted URL may bypass it. Include the origin in endpoint-dependent cache
  identity. Test absent production configuration at actual provider selection,
  while ordinary startup without this provider remains usable.
- [x] Introduce only the reusable ElevenLabs wire boundary needed for remote
  TTS; retain existing hosted-provider regression tests and scoped ownership.
- [x] Implement `MorseCodeApi.TTSSession`, truthful readiness, output credit,
  interruption, cancellation and stale-generation rejection.
- [x] Connect credentials, service catalogs, editor selections and Console
  label **MorseCodeApiTTS**. Advertise STT only after G passes.
- [x] Run a configured local room with real Go HTTP streaming: conversational
  output, opening audio and interrupted/replaced output. Assert no request is
  routed to ElevenLabs and no synthetic key reaches public events.
- [x] Inspect the changed Console service/editor states in headless Chrome via
  `agent-browser`, at desktop/mobile sizes, including unavailable service errors.

Foundation evidence (2026-10-14): four endpoint parser/configuration tests and
actual runtime-loader override/absence checks pass. Formatting, compilation,
Credo and unused-dependency checks pass. The full umbrella run reported one
Gateway five-participant WebRTC handoff timeout; that unchanged case passed in
isolation. Full integration acceptance remains open; see the
[implementation labnotes](../20261014-2120-implement-morse-api.md).

TTS integration evidence (in progress, 2026-10-14): the manifest, private
configuration, shared HTTP PCM reader, scoped request session, selection/startup
dispatch and telemetry now exist. An explicitly tagged `live_morse_code_api`
test calls the actual Go server and independently decodes its PCM at 8/16/24/48
kHz. Local acceptance passed against Go revision `b922e71` on loopback port
18796 using a caller-chosen key containing spaces. This proves the adapter's
HTTP path, not a configured room or hosted deployment. The Console service form
and model catalog are implemented; its desktop/mobile connection-success and
unavailable states have been rendered.

F acceptance (2026-10-15): Console's tagged configured-room test provisions an
encrypted platform service, saves/publishes a call, and independently decodes
real Go HTTP output for opening `SOS` and conversational `TEST`. It blocks sink
credit, interrupts the turn, accepts replacement PCM and retires the room. All
four observed synthesis requests use the selected origin; captured public events
contain no synthetic key. This uses a controlled embedded PCM recipient, not a
WebRTC/browser microphone. Chrome renders the editor's provider/model/voice
selection at desktop and mobile widths. Actual production runtime-loader checks
prove absent origin fails provider construction and configured HTTPS derives WSS.
The earlier full run passed every application except one stale Console provider
inventory assertion; its correction and focused regressions pass. The final
umbrella rerun remains in progress, so the milestone-wide final gates remain open.
See [configured-room evidence](../20261015-0003-morse-configured-room.md).

Exit: a saved service and published call spec produce audible Morse through
ordinary room output and remain interruptible under backpressure.

### G — Selectable MorseCodeApiSTT and room round trip

Dependencies: D, F; E needed for complete API acceptance, not the PCM room path.

- [ ] Red-test STT selection, acknowledgement readiness, credited input,
  allocation retirement, endpoint provenance and repeated transcript turns.
- [ ] Implement `MorseCodeApi.STTSession` using the focused compatible wire
  layer. Preserve room-owned turn IDs and scoped startup/failure handling.
- [ ] Implement a tested Morse-appropriate onset/endpoint profile. Do not copy
  Scribe's inferred-gap timers or local Silero behavior without proving their
  effect on tone gaps, partial revisions, forced segments and interruption.
- [ ] Add model catalogs and **MorseCodeApiSTT** selection; verify ordinary
  tenant/platform credentials, publication, restart and service readiness paths.
- [ ] Prove STT uses the same configured origin as TTS. Run the same saved call
  spec against two local server origins across a Vxpipe restart and verify the
  second receives all new STT/TTS/probe traffic. Use local TLS fixtures for the
  HTTPS/WSS path; hosted availability is not a prerequisite for local acceptance.
- [ ] Run a deterministic local-model room: injected independent Morse audio →
  remote STT → reply text → remote TTS → PCM output. Prove multiple turns,
  replacement, permission revocation and service loss without stale publication.
- [ ] Inspect Console transcripts/errors and service/editor states in rendered
  desktop/mobile browsers. Verify WebRTC/Opus separately if claiming that path;
  disable or document microphone processing that can suppress pure tones.

Exit: the two remote speech capabilities complete an ordinary configured room
round trip without paid speech/LLM services or local-codec bypasses.

### H — Complete compatibility and bounded performance acceptance

Dependencies: A–G.

- [ ] Finish the batch input-format matrix, multichannel/timestamp variants,
  discovery pagination/settings, model aliases and all remaining ledger fields.
  Include URL inputs only with bounded fetch/redirect policy and no local-network
  access; test media expansion limits as well as request byte limits.
- [ ] Resolve retention-dependent operations and Morse-specific semantic
  exceptions with the owner. Do not mark unsupported routes as full parity or
  silently return success. Record precise supported behavior and limitations.
- [ ] Run pinned official SDK conformance against the local service, with only
  base URL, synthetic key and documented Morse model/voice selection changed.
  Verify every HTTP and WS family, malformed input and cancellation.
- [ ] Add Go race, fuzz/property, disconnect/leak and overload checks at project
  boundaries. Test concurrent sessions with different keys/text/audio and no
  cross-session leakage. Enforce global and per-connection admission limits.
- [ ] Benchmark PCM/MP3 synthesis, recognition, first byte/partial/final latency,
  CPU, RSS, allocations and cancellation at 1, 10 and 50 concurrent sessions.
  Proposed target on a recorded 2-vCPU/512-MiB environment: 10 realtime PCM
  sessions without growing backlog, p95 server processing below one 20-ms audio
  frame, p95 PCM TTS first byte under 100 ms, cancellation under 250 ms and RSS
  below 384 MiB. Ratify or revise with evidence before accepting performance.
  Separate processing time from Morse timing, commit silence and network latency.
- [ ] At overload, reject boundedly and preserve admitted work. Record codec
  costs and replica/token constraints; Go alone is not performance evidence.

Exit: the ledger has passing evidence for every claimed behavior and explicit
owner-accepted exceptions; resource usage remains bounded on the declared load.

### I — Railway-ready handoff and hosted endpoint cutover

Dependencies: H for final acceptance. Container/configuration work can begin after
A and must be kept current as codecs and WS support arrive. The user owns Railway
deployment. Prepare and verify the full handoff locally without waiting for a
Railway account, domain or hosted endpoint; record hosted acceptance separately.

Preparation deliverables in the Go repository:

- [x] Add a pinned multistage `Dockerfile`, `.dockerignore`, current Railway IaC,
  `.env.example` and `docs/railway-deployment.md`. The image builds independently
  of the Vxpipe checkout, runs as nonroot and includes required codec libraries
  and CA certificates. Use an exec-form entrypoint for signal delivery; Go reads
  `PORT` directly rather than expecting shell expansion in Docker arguments.
- [x] Configure Railway's Dockerfile build, `/readyz` deployment healthcheck,
  healthcheck timeout and bounded restart policy using its current config schema.
  Specify `HOST=0.0.0.0`; honor Railway's injected `PORT` and route public traffic
  to that listener. Document settings managed in the Railway UI rather than
  implying repository config creates domains, DNS or runtime variables.
- [x] Serve HTTP and WS upgrades on the same port. `/healthz` reports process
  health; `/readyz` returns 200 only when codecs/catalog/server are usable and
  becomes unready during drain. Neither probe requires an API key or performs
  an external request. Configure any host filtering to accept Railway probes.
- [x] Handle SIGTERM with bounded HTTP drain and explicit WS closure/worker
  cancellation; Go HTTP shutdown alone does not drain hijacked WS connections.
  Align the shutdown deadline with Railway's configured termination grace period.
  Keep logs on stdout/stderr without bodies, keys or token query strings.
- [ ] Run the production image locally with a nondefault injected `PORT`,
  read-only filesystem and memory limit. Prove health, all streaming transports,
  SIGTERM exit, WS cleanup and restart with no retained content. No database,
  volume, migration, storage account or real ElevenLabs key is needed.
- [ ] Write the user's deployment runbook: connect the separate Go repository,
  select the Dockerfile build, set runtime variables/resource limits, keep one
  replica initially, deploy, check readiness, test the generated HTTPS domain,
  then add `morse-audio.definerun.com` and all Railway-provided DNS records. Include
  TLS/WSS checks, troubleshooting and rollback to the previous image/revision.
- [ ] Provide the base-URL-parameterized smoke command described above and run
  it against the local production image before handoff. Document separate
  commands for the generated Railway domain and custom domain, plus restoring
  Vxpipe's previous origin and restarting after a failed cutover.
- [ ] Include a deployment handoff record with separate local-preparation and
  hosted-verification results: Go/Vxpipe revisions, image identifier, selected
  origin, smoke command and outcome, unresolved gates, and previous verified
  origin/image for rollback. The record contains no keys or token URLs. Mark
  hosted results pending until the user's deployment has actually been tested.

Runbook references: Railway detects a root `Dockerfile` automatically; confirm
the selected builder in build logs. Configure `/readyz` as the deployment check,
but do not describe that check as continuous uptime monitoring. For custom DNS,
copy the CNAME and TXT records supplied by Railway and verify certificate
issuance before switching Vxpipe. See the official
[Dockerfile](https://docs.railway.com/builds/dockerfiles),
[healthcheck](https://docs.railway.com/deployments/healthchecks) and
[public networking](https://docs.railway.com/networking/public-networking) guides.

User deployment and subsequent verification:

- [ ] Record the user's deployed URL/revision after deployment. Verify HTTPS/WSS,
  actual Railway connection limits, drain behavior and early streamed bytes.
  Do not claim hosted checks passed from local Docker evidence.
- [ ] Set Vxpipe's `MORSE_CODE_API_BASE_URL` to the verified HTTPS origin and
  restart after draining calls. Repeat service discovery/probe, TTS, STT and
  configured-room checks with unchanged provider IDs, call specs and credentials.
- [ ] Add an explicit `live_morse_code_api` integration lane using synthetic keys
  and the existing `bin/livetests run` convention. Keep external/network tests
  excluded from default `mix test`; never inspect the protected credential file.
- [ ] Run hosted HTTP, both TTS WS modes, realtime STT and configured-room
  acceptance, including interruption, disconnect, restart and service outage.
  Document expected loss of active sessions/tokens on restart and recovery.
- [ ] Publish local startup, API/SDK examples, compatibility ledger, Vxpipe
  service setup, synthetic-audio injection, load evidence and rollback procedure.
  Link the two repository revisions and schema/fixture digest used for acceptance.

Preparation exit: a locally verified deployment package and complete runbook are
ready for the user. Hosted exit: HTTPS/WSS at the deployed host pass the same
contracts as localhost and Vxpipe switches through runtime configuration alone.
If the user has not deployed yet, report preparation complete and hosted checks
pending; leave I and the overall milestone unchecked.

Deployment specification correction, 2026-10-14: current official Railway docs
deprecate `railway.toml`/`railway.json`, exclude new services and specify a
2026-12-01 cutoff for legacy files. Use `.railway/railway.go` with a separately
pinned IaC SDK/module and a named service partial; keep the Go beta authoring
dependency isolated from the application. Validate the generated configuration
locally and document the user's plan/apply or equivalent UI workflow. Pushing
the repository does not itself apply IaC. This corrects the deployment mechanism
without changing the requested Railway destination or user-owned deployment.
See [Railway IaC](https://docs.railway.com/infrastructure-as-code).

## Final acceptance gates

- [ ] All nine checkpoints have code, focused red/green evidence and documentation
  in their owning repository. The API ledger has no unacknowledged incompatibility.
- [ ] Go: formatting check, `go vet ./...`, `go test ./...`, `go test -race ./...`,
  bounded fuzz/load runs and container build/smoke pass.
- [ ] Vxpipe root: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
  `mix deps.unlock --check-unused` pass. Run focused tests from their owning child
  during iteration; run relevant frontend checks for Console changes.
- [ ] Run `bin/verify-lean` whenever source-cutover or speech state-machine code
  changes; record the exact affected model/transition coverage.
- [ ] Default tests require no external deployment; separate local interoperability,
  rendered-browser and hosted evidence identify their inputs and limitations.
- [ ] Live claims identify the deployed Go revision, Vxpipe revision, protocol
  snapshot, test workload and results. No fabricated readiness, prices or speech
  recognition claims; local Morse and real ElevenLabs regressions stay green.
- [ ] Only then update this milestone and its index entry as complete.

## Specification review evidence

Local design review on 2026-10-14 checked capability ownership, prerequisites,
checkpoint ordering, endpoint injection, complete format/auth coverage,
retention conflicts, tone-specific turn boundaries and resource limits. It added
multi-context TTS, browser tokens, codec defaults, cross-language fixtures and
an explicit parity ledger so the initial PCM slice cannot masquerade as full API
support. This is a planning review, not implementation or hosted verification.
The endpoint/Railway revision additionally checks that local implementation and
deployment preparation do not depend on a live Railway service, while hosted
acceptance waits for the user's deployment. One origin reaches all provider
operations; configuration changes require restart, not call-spec migration.
The handoff review additionally requires the same explicit-origin smoke runner
for local and hosted acceptance, complete DNS instructions and a tested rollback
procedure. These are acceptance requirements; no implementation checkbox changes
as a result of this documentation review.
See [planning labnotes](../20261014-1947-remote-morse-milestone.md).

The follow-up delivery review makes the four-stage dependency order explicit and
adds a concrete handoff record to I. Local development and packaging can finish
before deployment; the runtime override survives hosted verification. Existing
implementation checkboxes are preserved. See the
[endpoint and deployment planning note](../20261014-2356-morse-deployment-plan.md).
