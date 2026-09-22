# STS recognition integration

- Integrate native Astra's finite-recognition checkpoint `b0b7d411` and reviewed
  deadline repair `aa67912c` onto main after Google caller checkpoint `3d3c7d5f`.
  Applied the exact 24-file delta from `d7c3af73`; preserved all subsequent main
  Google/handoff changes, including the new Google late-final real-room case.
- Parent inspected the production helpers, descriptor/event capability boundary,
  Morse finalization, focused fixtures/tests and normative documentation changes.
  Independent xhigh review found one queued-terminal expiry P2; the agent first
  recorded/reproduced it, then stored absolute expiry and checked it after terminal
  acknowledgement. Follow-up review clears that delta; source review is not a
  second test execution. Agent's expanded regression group: 152 tests, zero
  failures, with full red/green commands and terminal handles in its two labnotes.
- Finite recognition now aggregates bounded segments, requires ordered terminal
  proof and replaces successful recognizers before another reply can reuse them.
  Google/Deepgram sidecar admission remains rejected until hosted terminal support
  is actually implemented; ordinary human STT and private configuration remain
  supported. The agent is separately researching that still-required hosted
  protocol slice, not running hosted calls or expanding a manifest.
- Main Google checkpoint `3d3c7d5f` has 94 focused passing tests and all four
  post-commit static gates pass (handle `79358`, exit 0; strict Credo 1,083 files).
  The earlier full umbrella at `ebf11332` passed 2,363 tests; it does not verify
  these two new runtime checkpoints. Parent runs integrated focused checks next,
  then commits this coherent integration before broader gates.
- Parent integrated focused group completed in handle `57567`, exit 0:
  **228 tests, zero failures**, seed 0, two schedulers. It combines the agent's
  152-test regression command with all current Google codec/session/output and
  actual-controller tests, plus the updated real-room suite. No compiler warnings.
- Google follow-up source review clears its first two P2s but identifies another
  ordering case: the interrupted model end arriving after the preserved caller
  ends can create false idle renewal. That separate Google checkpoint will record
  and reproduce the reversed ordering before repair; it is not a recognizer
  integration defect and is not claimed fixed by these 228 checks.
