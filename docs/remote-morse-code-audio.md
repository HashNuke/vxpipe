# Morse-code API design

Status: implementation in progress, 2026-10-14. The user approved a separate
Go service and clarified complete ElevenLabs TTS/STT compatibility as the target.
Implementation is tracked in the
[Morse-code API milestone](../labnotes/milestones/remote-morse-code-audio.md).

## Decision

Build `morsecode-audio` as an independent Go HTTP/WebSocket service. It translates
text into Morse audio and supported Morse audio into text behind ElevenLabs-shaped
speech APIs. Deploy it on Railway at `morse-audio.definerun.com`. Accept arbitrary
nonempty API keys for compatibility; no registration, key database or ElevenLabs
account is involved. Keep processing transient with no retained content.

Vxpipe adds the fixed `morse_code_api` provider, displayed as MorseCodeApiTTS and
MorseCodeApiSTT, using its ordinary encrypted credential, catalog and scoped speech-session
boundaries. The standalone service does not import Vxpipe or call its local Morse
implementation. Independent signal fixtures and cross-language interoperability
tests establish shared audio behavior.

Go is a reasonable implementation choice for incremental DSP and concurrent
network streams, but capacity is an acceptance measurement, not a language
guarantee. Keep packages cohesive: Morse codec, audio formats, speech protocol,
authentication, catalog and server lifecycle. Use the standard HTTP library and
a maintained WS library; codec libraries own compressed audio support. Bound
admission, buffers, decoded duration and cancellation at each boundary.

## Compatibility contract and constraints

The target includes binary/timestamped HTTP TTS, single/multi-context WS TTS,
batch/realtime STT, read-only model/voice discovery and speech authentication.
The [official TTS reference](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
defaults to MP3; PCM-only support is therefore an intermediate checkpoint.
The complete schema/field/format inventory must be pinned during implementation.

Match the wire interface while documenting the changed domain: synthetic Morse
voices and models generate tones, and STT decodes tones rather than human speech.
Voice settings or semantic transformations without meaningful Morse behavior
need explicit documented treatment. Do not pretend an unsupported operation
succeeded or equate SDK parsing success with behavioral parity.

No persistence makes transcript retrieval, durable asynchronous jobs and
request-ID history stitching incompatible with their ordinary retained semantics.
The user has not separately approved those exceptions. The milestone requires
an explicit resolution and owner acceptance before claiming complete parity;
it does not authorize quietly adding storage. Ordinary synchronous and active
stream processing can proceed independently of that decision.

Single-use authentication tokens also need transient state. The proposed first
deployment uses one replica and bounded in-memory expiry/consumption records.
Restarts invalidate outstanding tokens. Multiple replicas cannot promise global
single-use consumption with separate memory; signing alone does not solve replay.
Replica expansion must revisit that contract without adding persistence implicitly.
The upstream [token API](https://elevenlabs.io/docs/api-reference/tokens/create)
defines speech-specific token purposes and a 15-minute lifetime.

No database, uploads directory, multipart spill, stored transcript, audio cache
or persistent job queue belongs in this service. Content and credentials stay
out of diagnostics. Arbitrary accepted keys are compatibility fields, not an
authorization boundary. Vxpipe nevertheless uses its normal secret handling.

## Existing integration evidence

Repository inspection found the following implementation boundaries:

- `apps/vxpipe_providers/lib/vxpipe/providers/registry.ex` owns the fixed manifest
  registry; existing Morse advertises STT/TTS/STS and ElevenLabs STT/TTS.
- Concrete speech implementations live under
  `apps/vxpipe_call_engine/lib/vxpipe/providers/`, despite their provider namespace.
- ElevenLabs `tts.ex` uses HTTP `/stream` with raw PCM; `scribe.ex` uses realtime
  WS and 16-kHz PCM. Both hold endpoint fields, but their validated constructors
  currently reject arbitrary endpoint options. A base-URL configuration needs
  deliberate tested plumbing through requests, sockets and runtime construction.
- `capability_catalog.ex`, speech runtimes and Console service/editor catalogs
  also contain explicit provider selections. Adding a manifest alone is insufficient.
- Local Morse `Config`, `Alphabet`, `Encoder` and `Decoder` define a usable
  interoperability baseline. Its defaults include 700-Hz tones, 60-ms units,
  amplitude 4096, 16-kHz mono PCM and a 14-unit trailing gap.
- Current ElevenLabs STT separates committed segments from inferred turn endings.
  Morse pauses require their own tested timing contract. Human-speech Silero VAD
  cannot be assumed to detect those tones.

Share only focused wire behavior between ElevenLabs and MorseCodeApi. Keep
model discovery, endpoint policy and tone-specific semantics explicit. Private
runtime configuration selects the remote origin; public call specs cannot route
credentials to an arbitrary URL. Preserve ordinary room ownership, backpressure,
readiness, permission retirement and output generation identity.

## Rejected alternatives

- Hosting the Elixir local provider as the remote application: conflicts with
  the requested independent Go project and would couple deployments.
- Registering a renamed local provider: bypasses the remote network/API behavior
  the feature is meant to exercise.
- Copying the entire ElevenLabs session implementation: duplicates ownership and
  protocol fixes. Extract only demonstrably shared wire behavior with regressions.
- A generic multi-provider gateway or new speech framework: broader than this
  integration and unnecessary for the existing capability boundaries.
- PCM-only endpoints advertised as full ElevenLabs parity: breaks default clients,
  encoded formats, timestamp variants and WS users.
- Recreating agents, billing, voice cloning or other ElevenLabs product APIs:
  excluded by the user's clarified TTS/STT scope.
- Durable token/job/transcript infrastructure: contradicts no persistence.

## Deployment implications

Use Vxpipe's temporary `MORSE_CODE_API_BASE_URL` runtime setting to develop against
the local Go server first. Development defaults to `http://127.0.0.1:8787`; test
servers use ephemeral ports. Outside development/test, selecting this provider
requires an explicit origin until hosted cutover. HTTP/HTTPS determines WS/WSS,
and discovery, credential probes, TTS and STT all use that origin. Validate it
centrally and keep it out of saved call specs and credentials.

After the user deploys the Go app, change the variable to its verified Railway
HTTPS URL and restart Vxpipe after draining calls. No code rebuild or call-spec
republishing is required. Keep the development override until a separate decision
retires it. A stopped local service must not trigger an implicit hosted fallback.
Document container-to-host networking separately from native loopback development.

The Go server separately reads `HOST` and `PORT`. Railway startup listens on
`0.0.0.0:$PORT`, exposes unauthenticated
health/readiness probes and drains active work within a bounded shutdown window.
Use HTTPS/WSS at the requested domain, a pinned container and initially one
replica. Railway's [public networking documentation](https://docs.railway.com/networking/public-networking)
describes domain/port routing; its [healthcheck documentation](https://docs.railway.com/deployments/healthchecks)
describes deployment readiness. Hosted tests must establish actual streaming,
WS lifetime and restart behavior; configuration alone does not prove them.

Prepare the Go project's `Dockerfile`, `.dockerignore`, `.railway/railway.go`,
`.env.example` and deployment runbook before handoff. Pin the nonroot runtime and
codec dependencies, use one HTTP/WS listener, and close WS connections explicitly
on shutdown. Test the image locally with an injected nondefault port, read-only
filesystem, memory limits and SIGTERM. Railway's
[IaC guide](https://docs.railway.com/infrastructure-as-code) now replaces legacy
`railway.toml`/`railway.json` for new services; legacy support ends 2026-12-01.
Pin the beta Go authoring SDK in an isolated deployment module and use a named
partial for this service. Explain the user's CLI plan/apply workflow and equivalent
UI settings: a repository push alone does not apply IaC. Domain/DNS and resource
allocation remain separately documented user operations.

Deployment is performed by the user. Local preparation is independently
reviewable; hosted tests and Vxpipe endpoint cutover remain pending until their
deployment exists. The milestone records those two acceptance stages separately.
Provide one smoke runner with an explicit base URL for the local production
image, generated Railway domain and final custom domain. Record each result
separately; a successful readiness probe alone does not establish streaming or
speech compatibility. Keep the previous Vxpipe origin available for rollback.

## Primary API references

Reviewed on 2026-10-14; refresh and pin exact schemas/SDK versions in checkpoint A.

- [Authentication](https://elevenlabs.io/docs/api-reference/authentication).
- [HTTP TTS](https://elevenlabs.io/docs/api-reference/text-to-speech/convert),
  [streaming](https://elevenlabs.io/docs/api-reference/text-to-speech/stream),
  [timed output](https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps),
  [timed streaming](https://elevenlabs.io/docs/api-reference/text-to-speech/stream-with-timestamps).
- [TTS WebSocket](https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-stream-input)
  and [multi-context WebSocket](https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-multi-stream-input).
- [Batch STT](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
  and [realtime STT](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime).
- [Speech tokens](https://elevenlabs.io/docs/api-reference/tokens/create).
- [International Morse reference](https://www.itu.int/rec/R-REC-M.1677-1-200910-I/en),
  inherited from the local-Morse milestone; recheck normative fixtures in B.

## Verification evidence

The Go server, authenticated discovery, HTTP synthesis formats/streaming, PCM
batch recognition and realtime STT are implemented. Pinned SDK discovery, all
four HTTP TTS routes, PCM round trips and repeated realtime STT turns pass,
including HTTP/AsyncAPI schema validation. Independent Morse fixtures and
Go/Elixir codec interoperability pass; these establish A–D, not full API
compatibility. `bin/setup` completed successfully. Full optional-field/TTS WS
conformance, Vxpipe provider integration, benchmarks, browser checks and Railway deployment remain
unchecked implementation acceptance gates. The
[planning labnote](../labnotes/20261014-1947-remote-morse-milestone.md) records the
separate specification review and exact planning validation.
