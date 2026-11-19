defmodule Vxpipe.CallEngine.Diagnostics.ManualCommitReportTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "manual sends stay distinct from text commits and use the latest successful send" do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      observe(state, [
        {:provider_landmark, generation, turn, :provider_text_commit, 100_000, 1_600},
        {:provider_landmark, generation, turn, :manual_commit_sent, 500_000, 8_000},
        {:provider_landmark, generation, turn, :provider_end_evidence, 700_000, 11_200},
        {:room_turn_completed, generation, turn, "turn", "command", 710_000}
      ])

    [first] = LiveReport.reports(state)
    assert first.durations_us.manual_commit_to_provider_end == 200_000
    assert first.durations_us.commit_to_provider_end == 600_000

    state =
      observe(state, [
        {:provider_landmark, generation, turn, :manual_commit_sent, 650_000, 10_400}
      ])

    [latest] = LiveReport.reports(state)
    assert latest.durations_us.manual_commit_to_provider_end == 50_000
    assert latest.revision > first.revision
    assert latest.landmarks_us.provider_text_commit == 100_000

    duplicate =
      observe(state, [{:provider_landmark, generation, turn, :manual_commit_sent, 500_000, 8_000}])

    assert LiveReport.reports(duplicate) == [latest]
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, current ->
      assert {:ok, next} = LiveReport.observe(current, packet)
      next
    end)
  end
end
