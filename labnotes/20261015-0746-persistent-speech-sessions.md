# Persistent speech sessions

The user requires realtime streaming transports owned for the participant's
capability lifetime for TTS, STT and STS. Per-utterance HTTP or WebSocket requests
are insufficient even when their responses stream audio.

- Initial worktrees were clean. Ran `bin/setup` successfully in the Vxpipe
  checkout; no live credential file was read.
- Audited current TTS, STT and STS startup/request paths. TTS mismatches exist in
  MorseCodeApi, ElevenLabs, Cartesia and Google. Existing STT and STS paths retain
  sockets across turns, with explicit Google/OpenAI lifetime policies.
- Read the milestone index and relevant semantic/provider/Morse/Google design
  contracts. Added a superseding decision and an unchecked implementation
  milestone rather than rewriting historical acceptance as a new guarantee.
- Confirmed ElevenLabs multi-context and Cartesia WebSocket wire contracts from
  official docs. Google AI Studio TTS remains request streaming; its docs
  distinguish exact synthesis from conversational Live output. Asked the user
  whether to disable incompatible call TTS or add a separate Cloud integration.
- Started the repository's `bin/teammate` in the `vxpag` tmux session for the
  three TTS adapter repairs and Go protocol support. Parent owns Google handling,
  cross-provider audit, documentation and final checks. Independent reviews of
  teammate results remain required before acceptance.
- A provisional Google exclusion regression failed at the expected manifest
  and call-selection boundaries. Removing its manifest entry made the intended
  policy change, but the user then questioned the distinction using Google's
  streaming TTS and Live Transcribe docs. Restored Google availability and
  removed the provisional exclusion tests pending clarification. Explained that
  streaming HTTP audio is valid synthesis and may reuse TCP/TLS; it does not
  provide a persistent multi-utterance synthesis session. No exclusion shipped.
- The user explicitly confirmed retaining Google streaming HTTP TTS as an
  exception while fixing persistent sessions elsewhere. Google runtime, model
  selection and manifest remain unchanged. Updated the normative decision and
  milestone to capture this scope. Existing Req uses Finch HTTP pooling, so
  per-request synthesis does not itself prove a fresh TCP/TLS handshake.
- Further independent audit found historical manual Scribe STT reopened its
  socket at each acoustic turn; removed that reconnect while retaining manual
  commits and local endpointing. Focused red run: 12 tests, 2 expected failures;
  initial green including continuous STT: 24 tests, 0 failures. A teammate
  verification pass and independent review found a mailbox assertion weakness;
  a follow-up is tightening proof of second-turn audio forwarding.
- Deepgram already retained its TTS socket, but a missing terminal response could
  leave generation/cancellation pending indefinitely. Added bounded generation
  and cancellation deadlines: initial red 16 tests/2 failures, green 16/0;
  teammate added retirement checks, resulting in 18/0. Independent review found
  no runtime defect in these deadline changes.
- User requested isolated live-provider checks only, without telephony. The
  runner initially refused because its reservation belonged to main. Confirmed
  no main checkout or active live runner; with explicit user approval transferred
  the stale reservation to the working branch. Credentials remain loaded only
  by bin/livetests; their file was not inspected or modified.
- Extended live TTS tests to two utterances and instrumented actual socket
  creation through thin test transports. Extended manual STT live acceptance
  with the same socket observation. Repeating identical telescope fixture audio
  twice returned a correct first transcript and an empty second transcript;
  this remains under investigation. Using distinct existing telescope/yes
  fixtures passed both acoustic turns on one socket (1 test, 0 failures, 6.3s).
  This passing test does not establish correct recognition of identical replay.

- Actual Cartesia TTS accepted two distinct phrases over one observed socket
  (1 test, 0 failures, 1.1s). Actual ElevenLabs TTS timed out after 30s because
  flush alone does not produce context completion. Independent review confirmed
  contexts must be closed explicitly; queued a teammate repair with cancellation
  races, final-frame PCM, unsupported Eleven v3 selection and transport cleanup.
- Actual Deepgram TTS passed cancellation while first PCM credit remained
  outstanding, followed by a successful new utterance (1 test, 0 failures, 6.2s).
- Raw persistent Scribe recognized two identical existing recordings when their
  original silence was preserved (1 test, 0 failures, 9.0s). This differs from
  the adapter's failing repeated-recording case. The adapter strips idle PCM;
  started a focused repair to preserve real PCM ordering without adding silence,
  delaying acoustic endpoints or reopening the socket. Both distinct and repeated
  adapter cases remain independently selectable live regressions.
- Go independent review found initial protocol errors, then exposed two further
  defects despite green existing race tests: cancellation could discard earlier
  flushed generation, and a saturated output queue blocked reading cancellation.
  Review overlay probes reproduced both. A second teammate fix pass is addressing
  these with stricter waveform and cancellation assertions before deployment.

- Shared TTS review fixes passed 41 focused tests, including actual local socket
  cleanup. Large provider PCM frames are split into credited 64-KiB submissions;
  queued stale idle timers cannot restart duplicate keepalive loops. Readiness
  waits for connection setup; cancellation fences audio and has a bounded wait.
  ElevenLabs and Morse explicitly close each flushed context and preserve the
  socket. Unsupported Eleven v3 selections fail configuration without fallback.
- Final isolated live TTS checks passed for ElevenLabs (16 seconds idle,
  cancellation and six successive phrases, 17.1s), Cartesia (cancellation and
  two phrases, 1.3s), and local Morse (all four rates, independent decoding,
  cancellation and subsequent utterances, 0.5s). Deepgram cancellation/reuse
  also passed earlier (6.2s). No telephony was used.
- Preserving real inter-turn PCM fixed repeated manual Scribe recordings:
  isolated replay passed 8.8s. A further 40-second silent-PCM test exposed the
  upstream automatic empty commit at about 36 seconds. Idle PCM bypassed the
  per-acoustic-turn commit budget. A focused repair now counts all transmitted
  PCM, with explicit idle commits that must not create speech events.
- Third Go review reproduced terminal-enqueue starvation and audio after an
  overload error, then accepted the repaired single-writer ordering and bounded
  enqueue policy. Independent probes and the complete Go race suite/vet passed.
  Browser inspection passed at desktop/mobile widths; no presentation tests added.
- Committed and pushed Go b81e882, tagged v0.1.4. Railway deployment
  c3d76d67-43b9-4baa-91e0-cc5e17fb1d78 reached SUCCESS with 0.5 vCPU and
  256,000,000-byte memory limit. Hosted llms.txt exposes the new endpoint.
  A hosted Vxpipe check initially lacked MORSE_CODE_API_BASE_URL and failed at
  configuration; rerunning with the explicit public origin. Binary CI pending.

- Go v0.1.4 GitHub CI and release both completed successfully; six platform
  archives plus checksums are published. Hosted smoke passed. The actual Vxpipe
  Morse integration passed against the public origin (1 test, 0 failures, 6.4s).
- STT review caught onset-time budget seeding for queued turns: preceding
  trailing silence can reach the wire after that seed, crossing the intended
  commit interval. A follow-up teammate pass seeds at first head transmission.
  The new silent-input tests also incorrectly equated received audio with
  transmitted audio despite retained preroll; their thresholds need correction.
  The initial pass was interrupted after stalling on these test diagnostics;
  its changes were retained and precise review findings supplied to the follow-up.

- The follow-up teammate confirmed the test threshold/alignment problems but
  stalled before implementing the fix. Parent took over, retained its useful
  diagnostics, removed temporary debug tests, and corrected the assertions.
  The queued-turn regression then failed for the actual missing wire accounting:
  19 tests, one expected failure. Seeding each turn once on its first wire
  transmission removed the stale epoch and odd-byte clamp; focused input, turn,
  session and room suite passed 30/0. Independent final review accepted it.
- Final isolated manual STT live run passed all three cases again (57.1s):
  repeated recordings, distinct recordings and 40 seconds silent PCM followed
  by speech. No replacement connection or telephony was involved.
- Final format, warnings-as-errors compilation, strict Credo, unused dependency
  and Lean gates passed. The first full umbrella run compiled the earlier test
  snapshot and reported its five known STT regressions; these are now fixed.
  Broader final verification is pending completion, not counted as green yet.

- The full umbrella run completed: all non-CallEngine applications passed
  (1,653 cases); its earlier CallEngine snapshot had only the five known STT
  test failures. Final CallEngine rerun passed provider regressions but exposed
  one unchanged room-lifecycle test receiving :noproc from a late monitor.
  That case selects only a fixture language model, with no speech capability;
  independent review found no direct changed-provider path. The log does not
  establish the earlier exit's cause. Isolated same-seed rerun passed 19/0.
  A sequential full CallEngine rerun is required before final acceptance.
- The live reservation was released and the owned local Go server/browser were
  stopped. Railway and the released binaries remain available.

- Final sequential CallEngine run passed all 2,223 tests with zero failures,
  75 exclusions, seed 714943 (198.8s). Together with the unchanged umbrella
  applications' 1,653 passing cases, current default coverage is 3,876 cases
  and 131 integration/live exclusions. No source edits followed this run.
  Final format/compile/Credo/dependency/Lean gates passed; docs and milestone
  are synchronized for the coherent implementation commit and push.
