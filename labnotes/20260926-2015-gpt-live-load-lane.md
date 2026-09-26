# GPT-Live duplex local load lane

Date: 2026-09-26. Starting revision:
`84710d6e655e10e7d835617cde7edf07e1dbed9c`.

## Work and decisions

- Added `:sts_duplex` to the existing compiled-room load harness, selecting
  `morse-duplex` with the provider's real-time clock. The CallEngine test
  configuration enables that provider without credentials or hosted traffic.
- The original harness expected room-initiated interruption. Duplex uses
  provider-owned barge-in, so it counts `AgentTurnCompleted.outcome:
  :overlapped`, records overlap latency, and requires zero room interruptions.
  Full reply checks exclude the overlapped output, whose spoken prefix may be
  shorter than `RECEIVED HI`.
- The first red integration run failed because `Room.plan/1` had no duplex
  case. The first smoke run after adding the case appeared green, but its
  report showed the surviving call stopped at three completed turns. A stronger
  expected-turn-count assertion failed red (6 versus 7 for two calls). The
  survivor gate now waits for its fourth reply; the corrected smoke passed.
- A command combining `--include integration` and `--only mode:sts_duplex`
  selected the other integration modes too. The focused reproduction uses
  `--only mode:sts_duplex`, which selects the tagged test under the default
  integration exclusion.

## Measured run

- Command: `bin/sts-call-load measured` from the repository root, exit 0.
  The run began after the prior umbrella suite finished; no build or test
  command ran concurrently. The host was x86_64 with four logical CPUs and
  7,750 MiB RAM. The script capped the BEAM at two ordinary schedulers, one
  dirty CPU scheduler, one dirty I/O scheduler, and two async threads. The
  reports show OTP 28 and Elixir 1.19.5.
- Four ten-call tests passed with zero failures. All modes had ten ready calls,
  nine healthy post-fault survivors, ten cleaned calls, and no reported errors.
  The original modes each completed 29 turns and ten room interruptions. Duplex
  completed 39 turns and ten provider-owned overlaps with zero room
  interruptions. The duplex report records 2,106 accepted input frames, zero
  ingress drops, zero rejected chunks, and zero incorrect decoded replies.
- Full machine-readable reports: [20260926-2015-gpt-live-load-lane.jsonl](20260926-2015-gpt-live-load-lane.jsonl).
  Each JSON line is the exact `CALL_LOAD_JSON` payload from the command.
- The duplex elapsed time was 12,529 ms. Startup p50/p95/p99 was
  64.8/72.1/72.1 ms, agent speech onset 1,035.8/1,259.6/1,259.9 ms, and
  overlap completion from barge-in 797.3/799.2/799.2 ms. These are synthetic
  local playback observations, not carrier or hosted GPT-Live capacity.

## Completion gates

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, and `mix deps.unlock --check-unused` passed after formatting
  the two changed test files.
- `PGHOST=/var/run/postgresql mix test` passed all nine umbrella child suites:
  2,835 tests, zero failures, 59 integration exclusions. The added exclusion
  is the tagged duplex load case, which passed in the measured lane above.
- No source-cutover or production speech state machine changed in this
  checkpoint, so the conditional Lean verification lane was not required.
