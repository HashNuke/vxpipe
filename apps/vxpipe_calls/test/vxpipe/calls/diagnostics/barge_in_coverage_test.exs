defmodule Vxpipe.Calls.Diagnostics.BargeInCoverageTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport
  alias Vxpipe.Calls.Diagnostics.Coverage

  test "an accepted incomplete row does not invent a storage counter mismatch" do
    g = make_ref()
    r = make_ref()

    state =
      observe(LiveReport.new(%{generation: g, clock_id: "clock", origin_us: -100_000}), [
        {:room_turn_started, g, r, "turn", "command", -60_000}
      ])

    [report] = LiveReport.reports(state)
    assert report.landmarks_us[:room_turn_completed] == nil
    now = ~U[2026-11-19 12:00:02Z]

    run = %{
      Vxpipe.Calls.TestLatencyRecords.run()
      | state: :closed,
        heartbeat_at: now,
        closed_at: now,
        counts: Map.put(LiveReport.counts(state), :dropped_audio_frames, 0)
    }

    coverage = Coverage.describe(run, length(LiveReport.reports(state)), now)
    refute :counter_mismatch in coverage.reasons
  end

  defp observe(state, packets),
    do:
      Enum.reduce(packets, state, fn packet, state ->
        assert {:ok, next} = LiveReport.observe(state, packet)
        next
      end)
end
