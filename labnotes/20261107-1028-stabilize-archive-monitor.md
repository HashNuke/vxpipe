# Investigate archive monitor termination

The asset URL checkpoint's complete root run (seed 774698) finishes with 4,992
tests, one failure and 263 exclusions. Format, warning-free compile, strict Credo
and the unused-dependency gate pass. All 548 Console tests pass. The failing case
is Persistence's `retries EctoStorage after its repository crashes and closes
without duplicates` in `ecto_storage_resilience_test.exs`.

The expected subscriber monitor message has exit reason `:normal`; the actual
message has `:noproc`. Repository observations include the recovered room-opened
fact and stored archive-stream-closed fact. The test currently attaches its monitor
after repository recovery, immediately before terminating the synthetic source.
Do not infer the cause solely from the exit reason. Astra is independently
investigating the lifecycle and seeking a focused reproduction before any change.
The full failed output is retained locally in the asset URL root verification log.

Astra's bounded diagnostic runs did not repeat the failure: one focused run, 100
and 1,000 sequential repeats, and 256 concurrent in-memory clones all passed.
The complete root failure remains the red evidence. Cross-process monitor-delivery
ordering is a hypothesis, not an independently reproduced root cause.

Move the monitor immediately after opening the subscriber, before `source_started`
and `offer`. The subsequent same-sender handoff messages and observed repository
attempts establish monitor installation before recovery/source termination. Keep
the exact normal-exit, fact-order and uniqueness assertions; additionally require
closure source_reason `killed` and incomplete `false`, so unrelated premature
closure cannot satisfy the strengthened case. No runtime implementation changes.
The focused original-seed run passes one test. All five root gates are rerunning.

Astra reviewed the actual moved monitor and strengthened closure assertions and
approved them without further changes. No assertion is weakened and no runtime
code changes. The root rerun remains the outstanding verification gate.

The first corrected root rerun is incomplete: it receives SIGTERM during Gateway
at 10:40:01 UTC and the command subsequently reports exit 1. Its earlier children
passed, and no new assertion failure is recorded before shutdown. This is not a
passing full run. The signal source is being checked before starting a fresh run;
no reason for the termination is inferred from partial output.

Astra confirms it issued no process termination or group cleanup near the signal;
its archive diagnostics had already completed. Signal provenance remains unknown.
Started a fresh full run after confirming the earlier command terminal, with an
owned PTY session and direct session polling for authoritative liveness/status.

The fresh root run completed with exit 0: all five root gates pass, 4,992 umbrella
tests with zero failures and 263 exclusions (seed 774698). This includes all 490
Persistence tests and 548 Console tests. The focused strengthened monitor case and
full suite are green; the original timing cause remains unconfirmed. The interrupted
run above is retained as incomplete evidence, not counted as a passing run.
