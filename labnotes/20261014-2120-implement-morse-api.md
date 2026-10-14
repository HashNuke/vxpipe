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
