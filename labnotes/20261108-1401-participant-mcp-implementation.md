# Participant-owned MCP implementation

Date: 2026-11-08. Starting revision: `09d8a49f` on `main`.

## Goal and checkpoints

Implement the complete participant MCP milestone and ownership design, including
durable tenant catalog maintenance. The user requested small committed/pushed
checkpoints, `pushnotify` progress, and GPT-6 Astra xhigh review before every
commit. Reproduce reported bugs before changing behavior; repeat review until
valid findings are resolved. The milestone's existing acceptance scope remains.

`bin/setup` completed successfully before implementation, including dependencies,
the existing ExMCP patch, assets and isolated development/test migrations.
Read the current ownership/milestone contracts and prerequisite runtime boundaries.

## Checkpoint 1: exact session incarnation retirement

The initial reviewer identified a concrete stale-handle risk: `close(connection)`
discarded its process identity and closed whatever session currently occupied the
credential key. The integration supervisor could also restart its client while
keeping the old owner identity. Both findings were reproduced before the fix:

- `mix test test/vxpipe/mcp/connections_test.exs` in `apps/vxpipe_mcp`:
  10 tests, 2 failures, seed 60733. Closing old A removed replacement B; killing
  A's client did not retire A's owner.
- Changed handle-close to terminate its exact integration supervisor PID. Kept
  the existing explicit key-close operation while consumers are migrated later.
- A session client is now temporary/significant, and its supervisor automatically
  terminates when that client exits. The session supervisor itself is temporary;
  a caller must explicitly open a fresh incarnation instead of inheriting a
  silently replaced client. ExMCP's internal protocol reconnect remains separate.
- Focused connection and telemetry checks passed: 13 tests, zero failures,
  seed 83524. A subsequent small refactor preserved key-close behavior even when
  only the owner is registered; the root gates include that final form.

- Independent GPT-6 Astra xhigh review approved the checkpoint with no valid
  findings after inspecting the reproduction, source and documentation.
- All five root gates passed on the final implementation: `mix format
  --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test`, and `mix deps.unlock --check-unused`. Umbrella tests report 5,002
  tests, zero failures and 265 excluded, seed 258421; the run took 747.4 seconds.
  No source-cutover or speech state machine changed, so Lean was not required.
- Changed documentation links and `git diff --check` pass. No UI changed.

T1 remains incomplete: this checkpoint does not yet relocate clients, own ExMCP's
transport workers, bound retirement or remove the global call-session cache. No
complete call teardown or performance claim follows from these identity tests.

## Next transport boundary

The next red tests should hold a real asynchronous POST and an active GET stream,
then exercise session close, forced client death, normal client stop and explicit
disconnect. Observe worker DOWN and peer socket closure, not only the binding
owner. The reviewer confirmed a per-session worker-supervisor hook can pass
through ExMCP transport options; references must include the exact incarnation.
Plain links alone miss normal exit/disconnect. Direct disconnect and transport
recovery currently discard asynchronous task bookkeeping, while initialization
still blocks in the client callback. These remain source-observed targets for
reproduction, not new verified defects or completed acceptance.
