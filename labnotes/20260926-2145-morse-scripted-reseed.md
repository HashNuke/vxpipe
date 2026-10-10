# Morse duplex scripted reseed

Date: 2026-09-26. Starting revision: `57a712a1`.

## Work and decisions

- The completion plan requires local `:expired` and `:connection_lost` close
  scripts for Morse duplex. A focused capability test went red because the
  profile rejected `scripted_closes?` and the provider had no `script_close/2`.
- Added an opt-in, manual-clock test control. A scripted close finishes the
  current burst, snapshots only `PublishedHistory` entries sent by the room,
  resets decoder/inference/segmenter/timeline clocks, and queues a brief Morse
  continuation when a burst was active or a caller turn was unanswered. An
  idle close waits for new input. A second close fails with `:reseed_failed`.
- Initially the reset discarded pending delegated calls. A regression failed
  red with `{:error, :stale_request}` when the room returned an in-flight tool
  result. The reset now preserves pending calls, and the result produces a
  spoken burst after reseed. A tool trigger is not repeated aloud in the
  line-cut-out prompt.
- A second regression failed red when a tool result queued during a hold
  disappeared across reseed. The reset now keeps held replies; releasing the
  hold plays both the result and the continuation prompt in order.
- Kept the response context and admitted old output while resetting the local
  generation. A mid-burst test settles the old output and the new audible
  continuation. The focused design record is
  `labnotes/20260926-2218-morse-duplex-scripted-reseed.md`.
- The first strict Credo run found the session module above its line limit.
  Moved the reset and continuation queue into a focused `ScriptedReseed`
  module; the focused suite and strict Credo then passed.

## Verification

- Focused CallEngine duplex capability, conversation and descriptor files:
  33 tests, zero failures with seed `963322`.
- Format, warnings-as-errors compile, strict Credo (1,134 files, zero issues),
  unused dependency, and Lean verification checks passed.
- The umbrella suite ran 2,852 tests with one Gateway WebRTC handoff timeout
  and 59 tagged exclusions. The failure was in
  `HumanTransferWebRTCTest` while waiting for 250 Hz audio on a newly
  reconnected observer sink; it reported `held?: true`. That case passed alone
  on rerun (one test, zero failures, 67 location exclusions). The CallEngine
  umbrella child passed 1,661 tests with zero failures.
