# Scribe appended short answer

Status: open follow-up; accepted as nonblocking on 2026-10-11 under the user’s
first-partial speech-start criterion in [Transcript start and optional VAD](../milestones/transcript-start-and-optional-vad.md).

## Reproduction

Run the existing, explicitly tagged live test through the credential-isolating runner:

```shell
VXPIPE_TRACE_SCRIBE=1 bin/livetests run --only live_elevenlabs apps/vxpipe_console/test/integration/elevenlabs_configured_room_test.exs
```

The test publishes a tenant call spec and resolves its encrypted platform Scribe
credential through normal room startup. It streams public synthetic 16 kHz mono
PCM: ten repetitions of “The final word is telescope.”, a brief “Yes.”, and two
seconds of silence. Scribe uses `scribe_v2_realtime`, English, upstream VAD commits
and the default `speech_to_text.vad: false`.

Expected: one final caller turn retains both the earlier phrase and the appended
answer. Observed: the final turn contains “telescope” but omits “yes”. The unchanged
assertion fails with `long room turn lost its final segment`.

## Evidence and limits

- The original corpus delivers all 774,400 bytes to the socket send API unchanged,
  in order, on one connection (seed 906572).
- No observed provider partial or commit contains the appended answer. The common
  turn coordinator cannot retain a word absent from its upstream input.
- Adding a 300 ms pause before the answer still fails with all 784,000 bytes
  verified at that boundary (seed 901442). The original fixture was restored.
- Separate short/repeated-answer, long-input and bounded background-noise cases
  pass in both local onset modes. This failure is specific to the combined corpus
  tested so far; it does not establish general short-answer accuracy.
- The socket trace is not a server-side acknowledgement of each audio chunk.
  The evidence supports a hosted recognition limitation but does not conclusively
  isolate a provider defect.

See [room-audio research](../20261011-0737-scribe-room-audio.md) for the diagnostic
method. Tracing records counts, digests and fixture-word booleans; it does not log
credentials or raw transcripts.

## Resolution

Keep the live assertion enabled in its existing tagged lane. The user accepted the
recognition limitation as deferred scope for the speech-start milestone. Resolving
this issue still requires evidence that the full original corpus is preserved. Do not manufacture missing text, relax
the assertion or silently restore local VAD/manual commits to obtain a pass.
Further hosted probes need a distinct diagnostic question or changed provider
behavior. Telephony and public carrier endpoints are not prerequisites.
