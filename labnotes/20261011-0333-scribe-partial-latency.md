# Scribe partial transcript latency

## Question and scope

Measure whether the first nonempty ElevenLabs Scribe partial can supply a useful
speaker-start signal for interrupting agent output, with `commit_strategy: vad`.
Production defaults and room behavior remain unchanged during this experiment.

## Method

- Use the existing public synthetic English sentence and short-answer PCM fixtures.
- Send 16 kHz mono S16LE PCM in 20 ms chunks at real-time capture cadence.
  Send each chunk at its capture-end deadline; absolute monotonic deadlines avoid
  accumulating sleep drift. Receive transcript messages continuously while pacing.
- Wait for provider readiness before starting audio. Vary leading silence across 1, 2 and 3 seconds,
  append three seconds, and preserve the sentence fixture's existing silence tail.
- Three fresh connections per fixture; send two utterances on each connection to
  distinguish initial buffering from a later utterance after an automatic commit.
- First nonempty partial receipt is the signal time. Ignore empty partials.
- Acoustic onset is estimated using the first 10 ms window above -40 dBFS RMS;
  it is a reference for these clean fixtures, not manually annotated ground truth.
- Independently classify identical PCM through packaged Silero and ActivityBoundary.
  Record the backdated onset and earliest capture time at which the four-frame
  speech-start confirmation becomes available (rounded to the 20 ms chunk grid).
  This offline reference excludes inference and task dispatch overhead.
  The final measurement also performs live Silero inference on each streamed
  chunk and timestamps ActivityBoundary confirmation; the reported gap uses that
  timestamp and includes inference, but excludes room/task dispatch overhead.
- Print per-trial safe JSON including reference times, partial receipt and text
  from public fixtures, automatic commit receipt and pacing lateness. No credentials,
  session IDs or connection headers are printed.

## Inspection

The existing STTSession requires manual commits and emits speech-start from local
Silero evidence. Scribe and ScribeSocket already accept VAD strategy at the wire
boundary. A production migration would require changing the descriptor, turn
ownership and activity inference as well as the default configuration.

The official [commit strategy guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
explains initial audio buffering and automatic VAD commits. It also documents
empty and repeated partial keepalives, which cannot each become a new speech-start.

## Reproduce

```shell
VXPIPE_MEASURE_SCRIBE_LATENCY=1 bin/livetests run --only live_elevenlabs apps/vxpipe_call_engine/test/integration/elevenlabs_scribe_partial_latency_test.exs
```

Credentials are supplied by the existing runner. The private environment file was
not inspected or modified.

## Results

The exploratory live run is underway. Early sentence and short-answer trials both
show first nonempty partials more than roughly one second after acoustic onset.
The broader umbrella checks overlapped with this run and caused a 393 ms pacing
outlier. Treat that run as exploratory and repeat the measurement without those
checks running before reporting final latency results.


Exploratory fixed-one-second-preroll results (five observations per row):

| Fixture | Connection | Median from energy onset | Range |
| --- | --- | --- | --- |
| Sentence | Fresh | 1,044 ms | 945–1,082 ms |
| Sentence | Reused | 1,475 ms | 1,413–1,655 ms |
| Yes | Fresh | 1,245 ms | 1,143–1,249 ms |
| Yes | Reused | 1,395 ms | 1,371–1,471 ms |

All automatic commits preserved the expected public fixture word. The live
measurement passed. The standalone repeat varies preroll to avoid observing
only one initial buffering/cadence phase, in addition to removing suite contention.


## User steering and validation

The user requested numbers through `pushnotify`, then clarified that the
measurement test should remain but be disabled. It now skips unless
`VXPIPE_MEASURE_SCRIBE_LATENCY=1`, including when the ordinary ElevenLabs live
lane is selected. An explicit selection without that flag completed with the
measurement skipped and no hosted request.

No production code changed. A draft durable report was removed in favor of the
requested notification and these checkpoint notes. The variable-preroll run
still overlapped with umbrella checks, so the final measurement records live
Silero confirmation directly and reports its own pacing lateness.

Formatting, warnings-as-errors compilation and strict Credo passed on the initial
measurement lane. The full umbrella test run was interrupted during long Gateway
WebRTC checks to remove its contention; it was not a complete root-suite pass.
The Gateway lane reported no failures at shutdown. No production state-machine
changes require Lean verification.


## Final live Silero measurement

ElevenLabs Scribe v2 realtime, commit_strategy=vad: measured 12 clean synthetic utterances, 20 ms PCM chunks.

First nonempty partial AFTER Silero confirmed speech start (live inference): 1097.5 ms median (810–1369 ms range).
Sentence: 1098.5 ms median (810–1369 ms range).
Short “Yes”: 1097.5 ms median (900–1287 ms range).

From estimated acoustic onset to first partial: 1259 ms median (953–1501 ms range).
Silero confirmed onset in 151.5 ms median (131–172 ms range).
Fresh and reused connections tested, 1–3 s silence preroll. All utterances auto-committed. Pacing lateness max 39 ms.
This suggests roughly another second of agent speech before transcript-based interruption. Small clean-speech sample; excludes room dispatch/cancellation. Production unchanged. Measurement test kept, disabled unless VXPIPE_MEASURE_SCRIBE_LATENCY=1.

| Fixture | Round | Connection | Partial after acoustic onset (ms) | Partial after live Silero confirmation (ms) | Pacing lateness (ms) |
| --- | --- | --- | --- | --- | --- |
| sentence | 1 | fresh | 1047 | 896 | 29 |
| sentence | 1 | reused | 1468 | 1314 | 8 |
| sentence | 2 | fresh | 956 | 810 | 24 |
| sentence | 2 | reused | 1501 | 1369 | 6 |
| sentence | 3 | fresh | 953 | 821 | 36 |
| sentence | 3 | reused | 1432 | 1301 | 27 |
| short | 1 | fresh | 1254 | 1103 | 29 |
| short | 1 | reused | 1439 | 1287 | 32 |
| short | 2 | fresh | 1156 | 985 | 29 |
| short | 2 | reused | 1264 | 1092 | 28 |
| short | 3 | fresh | 1061 | 900 | 32 |
| short | 3 | reused | 1300 | 1142 | 39 |

Final opt-in live measurement passed; all twelve utterances had nonempty partials
and automatic commits containing the expected fixture word. Final formatting and
strict Credo passed. Unused-dependency check passed. The default skip was verified
with explicit live-lane selection. No production defaults changed.
