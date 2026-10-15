# Morse STT contract and session

Checkpoint G begins after F's configured-room acceptance in `752959aa`.
Read the existing Scribe configuration, socket, manual/continuous sessions and
tests, plus Go's realtime options/handler and decoder contract. The Go service
accepts `morse_stt_v1`, defaults to 840 ms silence and does not force segments in
this profile. Its 60 ms dot profile has a 420 ms word gap. This supports a tested
provider-gap boundary, rather than Scribe's human-speech VAD or inferred timer.

- Wrote four configuration/protocol tests first; all four failed on the absent
  Morse STT module while eight existing Scribe tests passed. Added a private
  origin/key configuration and fixed public model/PCM profile. Require a full
  matching server acknowledgement before readiness. Keys are HTTP header values;
  origin and keys are omitted from struct inspection and public options.
- Extracted bounded PCM/base64 JSON encoding and speech-message decoding into
  `ElevenLabs.STTProtocol`. Each provider still owns acknowledgement validation
  and segment interpretation. Scribe keeps its existing optional echoed fields
  and manual/VAD defaults. A refactor script initially used a root-relative path
  from the child directory; it made no edit, then was rerun from the root.
- The combined Scribe/Morse protocol tests pass (12). Expanded existing manual/
  continuous session regression coverage passes (37 tests, three integration
  tests excluded); the separately selected socket integration files pass all
  five tests. No hosted ElevenLabs request was made.
- Seven scoped-session tests initially failed before an owned wire could start.
  Implemented the Morse socket and session using the existing allocation tree,
  event channel and bounded socket transport. All seven now pass: acknowledgement
  readiness, transcript onset, revisions, empty keepalives, repeated equal turns,
  chunk splitting, retirement, startup timeout, stalled-draft timeout and socket
  loss. No synthetic endpoint is inferred from elapsed wall-clock silence.
- A real Go socket test passes against `b922e71` on loopback:18796. Independent
  Elixir synthesis supplies an E, a full seven-unit word gap, then another E and
  the utterance tail. The final is `E E` with one turn reference; a second equal
  utterance uses a distinct reference in the same session. This establishes the
  tone-gap contract and socket path, not ordinary configured-room integration.
- The F umbrella rerun completed with 3,826 tests, zero failures, 145 excluded,
  seed 72837. Its CallEngine portion ran before this STT implementation; it is
  not evidence of a full run for G. A fresh run is required for these changes.
- `bin/verify-lean` passes: nine Lean build jobs and one replay test. It checks
  existing modeled speech/source contracts; it does not model the new remote
  Morse recognizer's complete protocol. Focused runtime tests cover that boundary.
- The final combined provider regression lane, including local socket integration,
  passes all 60 tests. Root formatting, warnings-as-errors compilation, strict
  Credo and unused-dependency checks pass. A second formatting pass was needed
  for one multiline callback head; no behavior changed. A new complete umbrella
  run is active for the STT foundation. The owned Go smoke process was sent
  SIGTERM and its handle exited zero after the live test.

Design decision: share only the compatible packet codec; keep Morse's strict
profile and endpoint authority separate from hosted Scribe semantics. Production
STT selection, runtime dispatch, telemetry, Console catalog, real room round trip,
origin-switch rehearsal and failure/replacement acceptance remain G tasks. The
provider manifest stays TTS-only until those integration changes are ready.
