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
