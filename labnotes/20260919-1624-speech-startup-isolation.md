# Speech startup isolation verification

## Authorization and scope

The implementation goal was paused on a suspected shared-startup bottleneck. The user
required test evidence before treating that concern as instability, explicitly authorized
isolated process trees and Morse load tests, and requested audio/text/end latency evidence.
This work verifies the prototype; it does not resume migration or change runtime code.

## Controlled regression

Added `speech/startup_isolation_test.exs` with an acknowledged held initialization, eight
real Morse STT sessions and independent PCM for E. Each healthy session asks for a 100 ms
startup budget. At a 300 ms observation window none completes; releasing the held peer lets
all eight start and decode E. Actual startup-call duration is the final failing assertion.

- Seed 0: healthy control 6–7 ms; held-peer starts 301–302 ms; 4 tests, 1 intended failure.
- Seed 42: healthy control 1–2 ms; held-peer starts 301–302 ms. With the existing Morse
  codec/transport/room and 17 session tests: 39 tests, 1 intended failure.
- Existing per-incarnation initial startup and replacement/preparation connector controls
  both reach ready and final E before their own peer is released.
- Those existing runtime source files are unchanged (`git diff --exit-code` passed).
- Excluding only `startup_isolation_regression`, seed 21: 38 tests, 0 failures, 1 excluded.

This proves admission coupling introduced by the prototype and a deadline that starts only
when a shared-supervisor request is dequeued. It does not prove current calls lose media or
crash; the native semantic path has not been integrated into rooms.

## Latency workload

Added opt-in `bench/speech_latency.exs`, outside default test discovery. It compares the old
Morse capability under per-incarnation supervision with the new semantic facade. Barrier
synchronization occurs outside each measured turn. The independent 900 ms PCM fixture is
submitted unpaced in 7,680-byte and 21,120-byte chunks. Text and end timestamps follow
successful semantic acknowledgement. No Morse encoder supplies the expected transcript.

Initial smoke runs used 3 warmups / 20 measured turns per owner and exposed substantial
run-to-run variation. Increased to 10 warmups / 200 measured turns, at 1/8/32 owners with
three alternating repeats and interleaved normal/held-startup 32-owner scenarios. This
improves tail sample counts without claiming sustained capacity or independent experiments.

Final run: Elixir 1.19.5, OTP 28, 8 online schedulers; 7.5 seconds test execution; 68,400
successful measured turns; one benchmark test, zero failures. Includes 19,200 successful
turns from already-ready semantic sessions while another provider remained held (monitored
through the measurement and then explicitly released).

At 32 owners, existing versus semantic first-text p95/p99 = 2.195/4.793 versus 3.485/7.033 ms;
turn-end p95/p99 = 1.523/3.554 versus 2.105/5.257 ms. All three normal semantic repeats have
higher text/end p95, but the benchmark compares different pre-migration public boundaries.
Maximum text latency was 67.746 ms existing versus 28.855 ms semantic; report the full
distribution rather than selecting one statistic. No latency SLO is claimed or invented.

The canonical JSON is `20260919-1624-speech-latency-metrics.json`. It contains aggregate and
per-repeat p50/p95/p99/max and counts, without audio, transcript payloads, credentials or
machine-specific paths. Startup readiness is recorded separately with cold-start/small-sample
limitations. Audio admission pools the two documented chunk sizes. TTS/playback, hosted
recognition, paced audio and end-to-end call latency were not measured.

## What changed during verification

- An early shell search used an unmatched zsh glob; replaced it with a directory `rg` search.
- The benchmark uses owning supervisor PIDs returned by `start_supervised!`, rather than
  attempting to call the RoomCapabilitySupervisor's private naming function.
- A broader test run revealed a race in the original startup-timeout assertion: bounded OTP
  startup can terminate before the channel emits its optional timeout notice. Corrected the
  test to require safe startup failure, provider DOWN and no early-ready event, independent
  of which timer wins. No runtime implementation was changed to make that test pass.
- Updated milestone/index/contract/README and the focused durable evidence document.

## Review and decision

GPT-6 Astra xhigh independently reviewed isolation causality, cleanup, measurement methodology
and the final JSON. It confirmed the startup defect and measured overhead while requiring
clear limits: these are synchronized local bursts, samples are correlated within three
repeats, startup samples retain cold effects, and lower held-run values do not prove an
improvement. All active-session turns succeeded in the exercised workload.

Keep implementation paused. Do not migrate rooms, claim checkpoint A complete, or commit it
as an accepted checkpoint. Revisit startup isolation and admission-time deadlines, then make
the red regression green before integration. No rollback is currently needed to restore the
old call path. Durable decision and exact reproduction commands are in
`docs/speech-startup-isolation.md`.

## Final verification

`mix format --check-formatted` passed from the root, as did an explicit formatter check
for the opt-in benchmark. `mix credo --strict` passed. `git diff --check`, changed-document
local-link checks and the JSON total-turn assertion passed. The full root test suite was
not claimed green: the diagnostic intentionally retains the failing startup regression.
Final git status preserves all prototype changes, with no runtime edits by this verification
turn, no checkpoint commit and no rollback. A pushnotify update reports the measured evidence
and paused state.
