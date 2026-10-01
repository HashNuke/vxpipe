# Scribe long VAD experiment

## Purpose and bounded request

Verify whether a longer native VAD stream produces intermediate commits before
the deliberately appended silence. Reuse the existing public 16 kHz PCM sample;
remove only its generator's known 64,000-byte zero tail. Repeat the remaining
69,120-byte phrase nineteen times, producing 41.04 seconds, then append two
seconds of silence. One connection accepts 43.04 seconds; the test rejects input
over 45 seconds. No manual commit, fixture generation, retry or other paid case.

## Observed result

Run the existing credential-loading runner with only `live_elevenlabs` and
`apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_long_vad_test.exs`.
The test passes: one test, zero failures, 44.0 seconds, seed 364893.

| Receipt phase | Accepted client audio | Transcript bytes | Known fixture word |
| --- | --- | --- | --- |
| Repeated speech | 36,000 ms | 40 | Present |
| Appended silence | 43,040 ms | 42 | Present |

The test records typed messages while pacing chunks with acknowledgements and
monotonic deadlines. Only phase/count/public-word booleans are printed; no raw
transcript, provider session ID or credential is logged. It requires stable
recognized text and tail settlement but does not assert segment events are
room turn ends. Ordinary tests exclude this live module.

## Interpretation and next decision

Receipt positions do not identify server processed-through audio or commit
causes. Repeated phrases are not a realistic uninterrupted acoustic corpus.
The speech-phase commit is consistent with a buffer-limit commit in VAD mode,
but this observation cannot prove that cause. It is insufficient evidence for
every segment commit to be an authoritative silence endpoint. Keep the
long-input turn gate open; do not implement native-commit-as-turn-end.

Next evaluate manual segment submission bounded below automatic limits, one
outstanding commit at a time, independently of acoustic endpoint ownership.
Missing/empty commit settlement must be investigated and fail safely, rather
than letting a timeout manufacture final text. No shared STT/STS contract is
changed and no production detector/session is added here.

## Mechanical follow-up and verification

After the paid run, derive the drain receipt byte count from actual submitted
audio instead of hard-coding this fixture's duration. This changes metadata
accounting only; the passing paid case is not repeated. Root verification for
the checkpoint is recorded below after execution.

All five root gates pass: format, warnings-as-errors compilation, strict Credo
(1,167 source files, no issues), default tests and unused-dependency check.
Root tests report 2,973 tests, zero failures, 91 exclusions, seed 536614.
CallEngine passes 1,766; Gateway passes 522; Console passes 194. The new live
probe is excluded by default. No live credential runner was invoked for these
follow-up checks. This change
adds an opt-in protocol experiment and documentation, without modifying speech
state machines or UI; no new Lean/browser acceptance is claimed or required.

The user requested external reference inspection during this checkpoint and
required that external project names and methods remain outside repository
documents. Inspection artifacts stay in temporary storage; no external code is
copied into Vxpipe. The repository records its own experiment and design gates.
