# Implement MorseCode API

## Start

- User authorized implementation, small commits and final Vxpipe push on branch
  `morsecode-api`; Go repository is `HashNuke/morsecode-audio`.
- Committed the reviewed plan as `93d3d1b8`. Cloned the empty Go repository.
- `bin/setup` completed successfully. Existing developer environment preserved.
- `pushnotify` startup notification succeeded. Use it for checkpoint updates.
- Go 1.26.1 is installed through mise but absent from the current PATH; use the
  pinned toolchain explicitly until repository tool selection is configured.
- Downloaded the public ElevenLabs OpenAPI schema for a content-hashed speech
  contract snapshot. No live speech requests or private provider file access.
- Asked the user to resolve the milestone's no-retention exceptions; independent
  synchronous/streaming work continues while that question is pending.

## Checkpoint A

- Initial red: API/config package tests failed because implementation packages
  did not exist. Green: focused tests, `go vet ./...`, `go test -race ./...`.
- Captured 13 HTTP paths and 53 transitive schemas, preserving fields/defaults
  and recording full/reduced source SHA-256 digests. Python SDK pinned to 2.72.0.
- Official SDK local discovery passed; six JSON response schemas validated,
  missing credentials rejected. Binary served a nondefault local port and exited
  cleanly after SIGTERM. Two different synthetic keys accepted.
- Complete WS contract snapshot and no-retention decisions remain open; A is
  partially complete, not an accepted full compatibility checkpoint.
- Go checkpoint committed as `468c387` (authenticated discovery service).

## Checkpoint B — PCM speech

- Added bounded incremental Go encoder/decoder, seven PCM rates, known ASCII Morse
  alphabet, manual/automatic commit and sample-derived character/word timing.
- Codec red: missing implementation package. HTTP red: both speech requests
  returned 404. Timestamp red: event alignment fields were absent.
- Independent square-wave SOS 2 fixtures exposed a partial-window defect at
  22.05 kHz; majority-active classification repaired duration estimates at all
  rates without accepting full-window wrong-frequency signals.
- Implemented explicit PCM HTTP synthesis and bounded multipart raw PCM/WAV
  recognition with no spill files. Full MP3 defaults and WS remain open.
- Real SDK red: three omitted optional form values arrive as JSON `null`;
  dedicated regression failed 422 before accepting only their null form.
- Response schema caught `logprob: null` despite SDK parsing success. Accepted
  codebook lookup now uses deterministic log(1)=0, explicitly not calibrated
  acoustic confidence; language is undetermined with zero language probability.
- Go focused tests, vet and race checks pass. Official SDK 2.72.0 round trip
  recognized SOS TEST 123 from 243840 PCM bytes; pinned response schema passes.
- CallEngine integration lane: two tests, zero failures, seed 263916. Covers
  Go→Elixir at 8/16/24/48 kHz and Elixir→Go multipart PCM at 16 kHz.
- Full Vxpipe root gate command completed with exit 0: format, warnings-as-errors
  compile, strict Credo, umbrella tests and unused-lock check. Console's final
  summary was 314 tests, zero failures (16 excluded); preceding application
  summaries were partially truncated by verbose debug output. No provider or
  speech-state-machine runtime changes exist in Vxpipe at this checkpoint.

## Contract-freeze continuation

- Captured all three official WS AsyncAPI documents (61 component schemas) from
  the canonical rendered documentation. Markdown URLs returned errors; extracting
  the embedded AsyncAPI YAML from canonical HTML succeeded. Stored structured
  schemas only, with source/specification digests; omitted reference prose.
- Verified snapshot hashes and every WS reference. Selected coder/websocket for
  framed transport ownership; dependency version will be pinned when used in D.
- Proposed explicit 501 errors for retained transcripts/webhook jobs and 422 for
  request-history stitching; owner decision remains pending for H acceptance.
- Go commits: `6a2622f` PCM speech and `d77418d` complete WS contract snapshots.
  A and B are complete; no compressed/WS implementation is claimed yet.

## Endpoint/Railway specification review

- Rechecked the user's endpoint and Railway requirements against F/G/I. Added an
  explicit native/container/TLS/Railway/cutover matrix and unavailability behavior.
  Discovery, credential probes and both speech capabilities share one origin;
  endpoint changes do not alter saved call specs or credentials.
- Kept local preparation separate from user deployment and hosted acceptance.
  Docker build, injected PORT, nonroot runtime, codecs, readiness, explicit WS
  drain and runbook are preparation requirements. Hosted acceptance stays open.
- Updated the companion design's stale prototype statement to the actual A/B
  evidence. This specification review does not mark F/G/I as implemented.

## Checkpoint C — HTTP formats, streams and timing

- Initial format red: format/encoder APIs missing; HTTP default MP3 returned 422
  and `/stream` returned 404. Timestamp routes separately failed 404 before code.
- Implemented all 28 nonstreaming formats and 21 streaming formats, MP3 default,
  bounded FFmpeg pipes, eight admitted synthesis requests and 30-second write/
  processing deadlines. Disconnect and deadline-write errors release work.
- Original/normalized alignment follows the source PCM clock. Packet framing
  preserves streaming bytes and emits completed characters once. MP3 physical
  decoded offsets can include codec priming/padding; documented for H review.
- Timed streams exposed repeated EOF becoming a closed-file error after joining
  the codec process. A dedicated regression failed before retaining EOF state.
- Independent decoding checks pass for every format. An early-output/cancel test
  leaves more than 290 seconds unrendered from a 300-second input. Official SDK
  2.72.0 consumes all four routes and validates both timestamp response schemas.
- Go formatting, vet and race checks pass. Committed HTTP implementation as
  `1210135`; no Vxpipe runtime code changed after the earlier full root gates.

## Early Railway preparation and specification correction

- Current official Railway documentation supersedes the original `railway.toml`
  proposal: new services use IaC; legacy config stops being read on 2026-12-01.
  Updated design/milestone accordingly. The user still owns actual deployment.
- Added `.railway/railway.go` using isolated pinned Go SDK v0.3.0. Its named
  partial owns only the Morse service. Local compilation/vet and rendered graph
  confirm Dockerfile build, `/readyz`, one replica, three failure retries and
  ten-second drain. Railway CLI/account plan/apply has not been run.
- Pinned Go/Debian image digests and codec packages; added a nonroot multistage
  image, allowlisted build context and deployment/cutover/rollback runbook.
- Codec startup red: availability-check function missing. Real synthetic encode
  checks now succeed and a missing executable fails; the binary checks before
  listening, so it cannot report readiness with unavailable codecs.
- The actual image ran read-only, UID/GID 65532, with 512 MiB and two CPUs and an
  injected container port different from the host port. All 49 binary format
  cases independently decode; official SDK discovery, speech and timed TTS pass.
- SIGTERM exited 0 without OOM, the read-only container diff was empty, and PCM
  SDK speech passed again after restart. Removed the test container afterward.
- Added a CI image lane for read-only injected-port SDK/format checks and clean
  SIGTERM, plus isolated IaC module compilation. No hosted service was changed.
- Go deployment preparation committed as `4a6bd80`; the HTTP format implementation
  is `1210135`. Documentation links, workflow syntax and diff whitespace pass.
- I remains incomplete: WS lifecycle/container checks, full compatibility/load
  acceptance, user deployment and hosted Vxpipe cutover are still pending.

## Checkpoint D — realtime STT

- Revalidated both clean worktrees and A–C commits before continuing. The prior
  turn made implementation/verification progress; no process wait was assumed.
- Pinned coder/websocket v1.8.15 after checking its current module metadata and
  framed transport API. Added focused protocol tests first; they failed 404.
- Added header-authenticated realtime recognition, six PCM rates plus mu-law,
  manual/Morse-silence commits, cumulative timestamps and audio-driven keepalive.
  Empty commits never create text; timing is a separate message after each final.
- The independent 22.05-kHz automatic-commit fixture timed out at an exact
  fourteen-unit tail. The fix accounts for one analysis window of boundary
  quantization; all rates still keep seven-unit word gaps within one segment.
- Added bounded admission for 64 upgrading/active sockets, a 512-KiB message
  ceiling, 256-KiB audio chunk limit, idle/write/lifetime limits and explicit
  cancellation/joining separate from HTTP shutdown. Disconnect releases capacity.
- Tests cover repeated turns, odd sample boundaries, a 500-character segment,
  separate sockets, malformed/oversized input, silent/current-partial keepalive,
  configurable silence, idle/lifetime expiry, admission and drain under race checks.
- Official SDK 2.72.0 recognizes two independently generated turns; every response
  validates against the pinned AsyncAPI and timings match cumulative audio offsets.
  The wire fields match the existing Vxpipe Scribe input/acknowledgement contract;
  no configured Vxpipe provider/session integration is claimed before F/G.
- The pinned read-only image passes realtime and HTTP SDK regressions. A dedicated
  drain script opens STT, stops the named test container and confirms socket close
  plus exit 0. The container was removed. CI now repeats these checks.
- Go vet, race suite, formatting, documentation links and workflow syntax pass.
  Existing CallEngine codec interop passes two tests, seed 736677. Vxpipe runtime
  and orchestration state machines did not change; this checkpoint updates docs
  only in the umbrella, with the earlier full root gates still applicable.
- Explicit limitations remain in the ledger: header-only auth until E, Morse
  commit defaults and unsupported semantic query fields until H. The earlier
  owner question about no-retention exceptions remains unresolved.
- After green checks, moved mu-law expansion into the transport-free audio
  package and reran focused race/vet checks. Go checkpoint committed as `7329afb`.

## Checkpoint E — token foundation

- Continued from current worktree evidence; the previous turn made a planning
  clarification, not further implementation. Committed D evidence and the endpoint
  handoff clarification as `4d218ae1`; sent the requested CLI progress notification.
- Reviewed pinned speech schemas and official token/authentication/batch references.
  Token issuance covers realtime_scribe, batch_scribe and tts_websocket. The latter's
  consumption waits for the TTS WS handlers; it is not claimed complete.
- Added external protocol tests first: issuance failed 404, CORS preflight 401.
  Added a bounded digest-only token registry with exact 15-minute expiry, purpose
  checking and atomic one-time consumption. It retains no keys or user content.
- Batch/realtime STT accept query tokens. Explicit tokens take precedence over
  header credentials; invalid/replayed/duplicate/wrong-route tokens fail without
  fallback. Successful authentication consumes before payload/upgrade validation.
  Wrong-purpose attempts preserve a valid token for its intended route.
- Tests cover expiry boundaries without sleeping, capacity recovery, drain,
  replacement-server invalidation and 16 concurrent consumers admitting exactly
  one transcript. Browser-Origin STT works; API preflight and error CORS work
  without cookie authority. No rendered-browser acceptance is claimed yet.
- Full Go race suite and vet pass; focused race checks pass after test refinements.
  Official Python SDK 2.72.0 issues/schema-validates all token types, consumes
  batch/realtime tokens and validates repeated STT events. Raw token-only requests
  prove no key is needed; replay/purpose checks pass. CI includes the token runner.
- Stopped the older D test server and verified its process handle exited 0.
  TTS WS, their token consumption/initial authentication and provider integration
  remain active work; E and the milestone remain unchecked.

## Checkpoint E — incremental synthesis foundation

- Token work is committed in Go as `1a4255a` and its milestone evidence as
  `d3adfe1b`. Sent a CLI progress update; no repository push or hosted deployment
  is claimed before final acceptance.
- Added failing tests for a transport-free incremental text planner. Reusing
  a complete utterance encoder for every WS message would insert fourteen units
  of silence between fragments; the planner instead carries a pending gap and
  emits that tail only at finalization.
- Independent E/T intervals prove one/three/seven-unit timing, no early tail and
  cumulative alignment. Eighty-four seeded fragmentation cases across seven rates
  reproduce finite PCM, normalized text and alignment with arbitrary byte reads.
  Unicode whitespace, invalid-fragment atomicity, stream limits, empty input and
  one-way finalization pass. Full Go race suite and vet pass after implementation.
- The planner owns no goroutines or audio queues; WS handlers must still enforce
  bounded queues and connect continuous codecs. Original-text alignment, context
  scheduling and transport behavior remain unchecked.
- Reviewed live canonical TTS WS pages against pinned AsyncAPI and SDK 2.72.0.
  Documentation examples use snake_case final/alignment fields, while the schema
  and Python FinalOutput types use camelCase `isFinal`. Use the pinned SDK/schema
  contract for output and document this discrepancy during WS conformance work.

## Checkpoint E — continuous codec lifecycle

- Incremental synthesis is committed in Go as `e9dea0b`; milestone evidence is
  `787ffb28`. Added a separate live encoding boundary because the existing finite
  encoder explicitly assumes its input never blocks awaiting future network text.
- New tests first failed on the missing EncodeLive function. The initial live
  implementation then timed out for MP3, Opus and both G.711 formats while waiting
  for audio before producer EOF. Known-PCM bounded probing removes FFmpeg's
  default stream-analysis buffering without discarding input packets.
- All 21 streaming formats now emit an actual audio packet while the producer
  keeps input open after 600 ms of PCM. Independent decoding checks duration/tone
  energy; PCM remains byte-identical. This proves incremental pipeline behavior,
  not a measured network-latency target or WS endpoint conformance.
- Live output closes its source before joining the codec/input copier. Tests
  cover cancellation/close while input is starved, codec child failure, missing
  codec, invalid WAV startup and pre-cancelled context. Normal PCM EOF cleanup
  exposed a subsequent closed-pipe error; retaining the terminal read result fixes
  repeated reads and all format regressions. Full Go race suite and vet pass.
- The transport must still supply bounded queues and source Close semantics,
  implement single/multi-context messages and alignment, and prove context/socket
  ownership under cancellation. E remains incomplete.

## Checkpoint E — single-context TTS WebSockets

- Revalidated worktree/process state; the previous goal turn progressed the
  deployment acceptance specification. Committed that documentation as `6b17d0af`.
  The earlier Python smoke process had exited; the native server remained live.
- Completed the pending handler work and committed Go `601f8cf`. Initial tests
  had failed 404/401 before implementation. The handler preserves Morse gaps
  across fragments, emits audio before future input, supports repeated flush and
  emits one final plus close 1000 at EOS. Output codecs/queues have explicit bounds.
- Header, bearer query/header, initialization key/bearer and single-use tokens
  pass; invalid explicit tokens never fall back. Five-second initialization,
  malformed frames/options, queue/capacity errors, disconnect and drain pass.
  Full Go race suite and vet pass. No HTTP bearer or multi-context parity claim.
- Python SDK 2.72.0 forces WSS for an HTTP base URL, so local acceptance uses
  trusted TLS termination with unchanged byte forwarding. Intermittent stalls
  occurred before any HTTP upgrade reached Go. Changing Python versions or
  isolating the SDK in a subprocess did not eliminate them. Disabling session
  tickets in the temporary fixture yielded ten consecutive successful PCM/MP3
  runs across Python 3.12/3.13; the upstream OpenSSL ticket hazard is a plausible
  explanation, not a proven root cause. Certificate verification remains enabled,
  the SDK is unmodified, and hosted URLs bypass this fixture entirely.
- Pin websockets 17.2 for repeatable protocol tests. The upstream final schema's
  optional-only shape overlaps audio in oneOf; validate selected branches and
  independently assert terminal ordering rather than silently editing the pin.
- Built the exact production image; SDK discovery, HTTP TTS, batch/realtime STT,
  token and TTS WS checks pass on an injected nondefault port. Chrome 154 from a
  separate origin passes first-message/token TTS (48,000 bytes, one final, normal
  close) and independent E token STT. No audible playback or browser SDK claim.
- Extended CI and drain fixtures to active STT plus open-input PCM and MP3 TTS.
  The read-only 512-MiB/two-CPU container exited 0 without OOM or filesystem diff;
  removed that owned test container. Python syntax/document links and diff checks
  pass. Sent start and checkpoint CLI notifications. E remains incomplete and
  the milestone remains 4/9; multi-context TTS, Vxpipe integration and H/I remain.


## Checkpoint E — multi-context TTS completion

- Go commit `b922e71` implements independent contexts with a coordinator owning
  input, deadlines and socket writes, per-context serial workers, bounded output
  and round-robin publication. It reuses the existing generation encoder rather
  than duplicating the Morse/codec implementation.
- Initial route tests failed 401/404. The first implementation confused source
  EOF cleanup with explicit cancellation and lost tails; an independent abort
  marker fixes this and suppresses queued stale output after close is processed.
  Another focused red test exposed initialization credentials rejected on a new
  context; valid credentials now work there without permitting active mutation.
- Reviewed the pinned SDK's detailed CloseContext contract: already-flushed work
  continues after close. Preserve that output, cancel only unflushed work and
  serialize immediate ID reuse behind the retiring context. Empty text is a
  keepalive, not EOS. Close-socket flushes all contexts before normal completion.
- Go race tests cover independent producers, repeated lifecycles, five-context
  admission, token replay, default context, idle closure and per-context refresh,
  ready-output fairness, global overload and disconnect/drain of MP3 workers.
  Both TTS routes now run the full credential-location and initialization-timeout
  tests. Full race suite/vet and focused follow-up tests pass.
- SDK 2.72.0 has multi-context message/response models but no high-level transport
  implementation. The runner uses these unmodified models, a plain WS transport
  and pinned AsyncAPI validation; no nonexistent SDK client acceptance is claimed.
- Rechecked upstream auth docs: general HTTP uses xi-api-key, realtime STT adds
  its token query, and bearer query/initial fields belong to TTS WS. Do not invent
  a requirement for general HTTP bearer auth from those TTS-specific bindings.
- Native Chrome 154 cross-origin interruption passes against the production
  image: canceled E emits 1,920 bytes, replacement T emits 32,640, each has one
  final, normal socket close. Single-context key/token and independent STT browser
  checks remain green. No audible playback or Console UI acceptance is claimed.
- The read-only 512-MiB/two-CPU image passes single/multi SDK/schema checks and
  SIGTERM with STT, single PCM/MP3 TTS and two multi-context MP3 encoders active.
  Exit is 0, OOM false and filesystem diff empty; removed the owned test container.
  CI includes multi-context checks and expanded drain. Documentation links,
  Python syntax, formatting and diff checks pass.
- Sent the requested CLI checkpoint notification. E's transport/lifecycle gates
  are complete; milestone/index now show 5/9 (A–E). F/G provider integration,
  H complete semantics/load/owner decisions and I hosted acceptance remain open.
  No push, Railway deployment or whole-goal completion is claimed.


## Checkpoint F — private endpoint foundation

- Inspected actual provider manifests, shared credential/probe contracts,
  ElevenLabs TTS configuration/request/session modules, capability/model catalogs,
  plan startup and private runtime resolution. Existing TTS constructors reject
  endpoint options; the upcoming integration needs a named provider and private
  configuration boundary, not a public URL option or registry-only change.
- Added a focused endpoint test before implementation: three tests failed on the
  absent module. The new Providers-owned Endpoint validates a single HTTP(S)
  origin and derives its WS/WSS counterpart. It preserves selected ports, accepts
  container DNS and IPv6, normalizes a trailing root slash, and rejects embedded
  credentials, query/fragment, paths, malformed ports and unsupported schemes.
- `config/runtime.exs` alone reads MORSE_CODE_API_BASE_URL. Development defaults
  to loopback:8787; test/production require explicit configuration when resolved.
  HTTP is permitted only with the development/test policy. The shared parser has
  no default host, network call, environment-file access or fallback. Four focused
  parser/configuration tests pass, including sequential local/hosted resolution
  and restoration of the test's application environment.
- Kept the provider out of the registry until its actual TTS capability and
  consumers exist. F/G remain incomplete; no UI, room, network-routing or cache
  separation acceptance is inferred from endpoint parsing. The next slice must
  add manifest, credential reachability probe, TTS configuration/request/session,
  model/catalog/startup/runtime dispatch and endpoint-dependent cache identity.
- Actual runtime-loader smoke checks pass with an explicit container-style HTTP
  origin and with the variable absent in the test environment. The first derives
  the matching WS origin; the second reports `:endpoint_not_configured`.
- Root formatting, warnings-as-errors compilation, strict Credo and unused
  dependency checks pass. The full umbrella test run exited 2: Gateway reported
  one timeout in `HumanTransferWebRTCTest`'s five-participant handoff while waiting
  for `:native_gate_waiting` at line 782 (603 tests, one failure, eight excluded).
  CallEngine passed 2,162 tests with 83 excluded and Providers passed 34 tests.
  The unchanged Gateway case then passed in isolation from its owning child
  application (one test, zero failures, 68 excluded; 172.7 seconds). This suggests
  a timing-sensitive failure but does not establish its cause or make the full
  suite green. Keep that evidence visible at the next full integration gate;
  no unrelated handoff behavior or test deadlines were changed.

## Wait-sound test synchronization found during F verification

- The next full umbrella run exposed `WaitSounds.PlayerTest`'s sink-replacement
  case receiving a retired sink's frame after its zero-time mailbox cleanup.
  `Player.reconcile/3` removes the sink but does not retract a request already
  queued in that sink. The test had no acknowledgement that this queued request
  had produced its observer message before clearing those pre-cutover messages.
- Added a sink `:sys.get_state/1` acknowledgement after reconciliation and before
  mailbox cleanup. This preserves the assertion that new output must not go to
  the retired sink, without adding sleeps, loosening deadlines or changing the
  player. The observed full-suite failure is the red evidence; the owning
  child's full player test file passes all 12 tests after the fix.
- The broader umbrella run remains active while this test-only checkpoint is
  recorded. Its already-running player test used the old source; final results
  and follow-up verification belong with the F implementation checkpoint.
