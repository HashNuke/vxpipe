# STS usage gate assertion

The socket-backed root `mix test --seed 0` after `7ed921af` exited 2. Its
high-volume Gateway log hid the failure summary in the tool output. Re-running
`mix test --failed --seed 0` with `PGHOST=/var/run/postgresql` showed the saved
Gateway case pass (1/0), but the Persistence STS usage case failed at
`usage_store_test.exs:201`.

The full Persistence child suite reproduced one failure among 186 tests. A
first isolated command at line 154 passed but selected the preceding test, so
it was not evidence for this case. The first hypothesis was a load-sensitive
2-second wait. Increasing that wait to 10 seconds on the exact line-160 case
was an informative failed experiment: the mailbox already contained the
expected completion, but the assertion still timed out. The capability sends
`{:vxpipe_sts_turn_completed, capability, agent_id, turn_ref, owner_sequence}`;
the Persistence test still matched a four-field tuple. The observation's
`6_300` millisecond quantity describes generated audio, not wall-clock test
latency. No runtime deadline change was warranted.

The final test asserts all five fields, pins the capability and exact agent ID,
and keeps the original 2-second bound. Focused case: 1/0, seed 0. Full
Persistence child suite: 186/0, 12 excluded, seed 0. Both used local PostgreSQL
peer authentication via `PGHOST=/var/run/postgresql`; no credentials were
created or logged. Post-commit root verification remains pending.
