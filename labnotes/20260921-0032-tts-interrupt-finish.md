# TTS interrupt finish

## Scope

The final milestone audit reopened checkpoint E after independent GPT-6 Astra xhigh review found
that interruption could overlap an outstanding sink `finish` request. This repair stays inside the
participant-scoped TTS tree: the existing persistent Output worker retains one output operation and
one interrupt operation, with no new process, queue, retry, fallback or shared authority.

## Reproduced failures

- The production sink order replies `{:error, :interrupted}` to a held finish before acknowledging
  the interrupt. A focused semantic test failed because the capability stopped with
  `:audio_output_failed`; `TextToSpeech.interrupt/1` returned `{:error, :unavailable}` and no
  replacement could run.
- A controlled sink acknowledged interruption while retaining the old finish reply. The provider
  accepted replacement input, but Output still held the old operation and silently received no
  replacement audio. The focused test failed at that exact audio assertion.
- A controlled successful finish reply reached the capability while cancellation was pending. A
  deterministic provider gate and mailbox acknowledgements showed the current phase changed to
  `:draining`; a late playback completion could therefore overtake cancellation.
- Review of the first repair found a fail-open timeout path. With a suspended sink, the new bounded
  interrupt returned `{:error, :sink_unavailable}`, but the capability converted it to zero played
  milliseconds and reported successful interruption. The red test expected unavailable and got
  `{:ok, [{request, 0}]}`.

These are deterministic project-owned protocol failures. None relies on scheduler timing, sleeps,
hosted services or a full application load.

## Repair

- A finish result of `:ok` or `{:error, :interrupted}` for the exact cancelling request settles the
  sink operation without changing cancellation authority, completing playback or failing the
  capability.
- A successful sink interrupt explicitly abandons the exact old push/finish request before replying
  to the capability. `:gen.receive_response/2` deactivates the request alias and flushes an already
  queued reply, so a late old reply cannot match or clear replacement output.
- Every asynchronous sink push, finish and interrupt now has one exact request-ID timer. Normal
  settlement cancels the timer; deadline settlement deactivates the alias; stale timer messages are
  ignored because their request ID no longer matches live state.
- Only `{:error, :wrong_turn}` remains a valid zero-playback interrupt result. Sink unavailability or
  timeout fails the scoped TTS capability with `:audio_output_failed`, which prevents replacement
  admission without proof that old audio stopped.
- The production request deadline is four seconds, leaving the public five-second capability call a
  one-second margin. The tree accepts an internal timeout override solely for deterministic boundary
  testing.

## Verification

- The four red paths pass after repair. The complete Output/semantic group passes 10 tests with zero
  failures, seed 0. GPT-6 Astra xhigh reviewed the final repair and found no remaining P0/P1/P2
  blocker.
- Five deadline/order cases ran 51 times in one VM: 255 executions, zero failures, four schedulers.
- The room/opening/private-transfer focused selection passes 84 tests with zero failures. The final
  umbrella run supersedes its earlier pre-timeout-repair Engine run.
- The unchanged semantic handoff workload ran three times on four schedulers. Every run completed 36
  trials, 3,936 TTS turns, 3,936 concurrent STT turns and 492 forced failure/replacement cycles with
  zero failures. Peak per-trial p99 first-audio/sink-acceptance values were 4.214/132.811 ms,
  1.152/66.191 ms and 2.458/75.020 ms. The first higher sample did not repeat; the last two are below
  the prior 2.665/85.237 ms milestone sample. Observed maximum safe-notification/teardown/replacement
  times were 2.911/2.912/6.949 ms across the three runs.
- Final umbrella gates pass under `ERL_FLAGS='+S 4:4'`: formatting, warnings-as-errors compilation,
  strict Credo, unused-dependency check, and 1,961 tests with zero failures and 42 excluded, seed 0.

The load lane uses four of eight schedulers and local Morse providers. It measures engine delivery,
sink acceptance and recovery boundaries; it does not claim physical playback, hosted latency or a
production capacity ceiling.
