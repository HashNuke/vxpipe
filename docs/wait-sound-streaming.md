# Wait-sound streaming

## Decision

`WaitSounds.Player` streams each run of a wait sound or cue to every sink as one output turn.
It keeps at most five 20 ms frames (100 ms) ahead of real time, scheduled from the run's
start, so a late timer or a busy scheduler never leaves the sink without audio. Pause and stop
interrupt the sinks; the interrupt reply gives the exact played duration, the cursor moves to
the least-played sink's position, and resume starts a new run from that frame. A finite cue
finishes its turn once and reports completion after actual playback and a drain on every sink.

## Why

The previous player sent one 20 ms frame, closed it as its own playback segment, and waited
for that segment's completion before building the next frame. Sinks play one turn at a time,
so every frame paid a full round trip with nothing queued behind it:

- Callers heard a gap after every frame on a busy server, and wait music and cues played
  slower than real time.
- The 250 ms transfer-recovery cue took 265 ms unloaded and up to 1,024 ms with the CPU
  saturated. Recovery has a fixed 750 ms budget, so failed transfers ended the caller's call
  (`:handoff_recovery_failed`); `OutboundPhoneTransferTest` failed 7 of 10 saturated runs.

## Rejected alternatives

- Raising the recovery budget. It hid the stretched playback and kept the audio gaps.
- Larger frames per segment. Fewer gaps, but still one per segment, and coarser pauses.
- Pushing until the sink applies backpressure. The telephony output queues up to 500 frames
  (10 s), so a pause or stop would wait for seconds of queued audio.
- Queuing several turns in the sink. The Gateway output and arbiter play one turn at a time;
  changing that is a larger core change with no added benefit for this player.

## Implications

- Pause and stop now take effect immediately instead of after the in-flight frame.
- A sink added mid-run joins at the next pushed frame, at most 100 ms ahead of the others.
- Tests that paused at an exact frame by observing per-frame completions now pause on the
  player directly and assert the recorded cursor is retained.

## Verification

Player tests written first failed for the per-frame protocol (no queued window, no
interrupt-based pause, per-frame cue finish). The Call Engine suite passes; the Gateway
WebRTC handoff suite passes repeatedly.
