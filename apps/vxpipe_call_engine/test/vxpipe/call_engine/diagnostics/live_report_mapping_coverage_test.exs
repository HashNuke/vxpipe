defmodule Vxpipe.CallEngine.Diagnostics.LiveReportMappingCoverageTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "the first provider mapping supplies the lower sample bound when there is no preceding end" do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    packets = [
      {:acoustic_boundary, 0, :speech_ended, 3_200, nil, 900_000, nil, :clock_uncertain},
      {:provider_sample_mapping, generation, 16_000, 16_000},
      {:acoustic_boundary, 0, :speech_started, 19_200, 1_200_000, 1_300_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 25_600, 1_600_000, 1_700_000, 1_000, nil},
      {:acoustic_progress, 0, 0, 32_768},
      {:provider_landmark, generation, turn, :provider_end_evidence, 2_000_000, 32_000},
      {:room_turn_completed, generation, turn, "turn", "command", 2_010_000}
    ]

    state =
      Enum.reduce(packets, state, fn packet, current ->
        assert {:ok, next} = LiveReport.observe(current, packet)
        next
      end)

    [report] = LiveReport.reports(state)
    assert report.durations_us.speech_end_to_provider_end == 400_000
  end
end
