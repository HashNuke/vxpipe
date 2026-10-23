# Morse realtime latency review

The user asked whether the 5.540-second TTS and 1.814-second STT p95 figures
represented single-request latency, and requested a performance code review.

- Reviewed Go API revision `4b481faa` and Vxpipe revision `0f1b9831`.
- Those figures include initial connection setup at 1,812 TTS / 531 STT
  concurrency. The load client records only the first turn's first-event
  latency; it cannot establish subsequent-turn latency under load.
- Ran three sequential connections with three verified SOS turns each for
  both services, locally and against `https://morsecode.vxpipe.com`.
  All 36 turns passed. Hosted TTS first audio after setup: 175–202 ms;
  hosted STT first partial after audio start: 648–653 ms. New connection setup
  added 263–311 ms TTS / 255–554 ms STT. Local first events were 0.3–2.0 ms
  TTS / 480.5–481.5 ms STT. Small samples are not production percentiles.
- Current Railway resources are 0.5 vCPU / 256 MB; original saturation tests
  used 125 MB. This probe does not isolate the effect of resizing memory.
- STT needs approximately 480 ms of signal to recognize the first S with
  the fixed 20-WPM profile. Reducing that by emitting guesses changes semantics.
- Vxpipe's TTSRequest opens/closes a WebSocket per utterance. A persistent
  call-owned socket could avoid repeated handshakes, but must preserve
  cancellation, completion, stale-audio handling and backpressure. No adapter
  change made during this review.
- Go decoder partials copy the full character timestamp history although API
  consumers use timestamps only from final events. A 1,000-E benchmark
  allocated 17.6 MB cumulatively; allocation profiling located the dominant
  allocation at partial construction. This is not 17.6 MB retained per socket
  and does not establish the cause of prior short-SOS failures.
- Encoder construction plus first 4-KB frame took about 24 microseconds;
  complete SOS rendering about 290 microseconds locally. Waveform computation
  and transport allocations are throughput candidates, not an explanation for
  several seconds of isolated synthesis time.
- Durable evidence and recommendations are in the API repository's
  `docs/latency-review.md`, linked from `docs/load-test.md`. No runtime changes,
  capacity-limit changes, or new CI tests were made. Temporary probes were
  removed and the local review server stopped after measurement.
- Verification: exact PCM count/hash and partial/final transcript checks on
  every probe turn; local codec CPU/allocation profiles; documentation diff
  and link checks. Full umbrella tests are unnecessary for these research notes.
