defmodule Vxpipe.CallEngine.Diagnostics.LiveReportMappingTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.{CapturePacket, LiveReport}

  defp base do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})
    {state, generation, turn}
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, acc ->
      assert {:ok, next} = LiveReport.observe(acc, packet)
      next
    end)
  end

  test "late nonzero mapping updates the same row and enforces sample coverage" do
    {state, g, t} = base()

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 100_000, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 100_512, 40_000, 90_000, 1_000, nil},
        {:provider_landmark, g, t, :provider_end_evidence, 70_000, 1_512},
        {:room_turn_completed, g, t, "turn", "command", 71_000}
      ])

    [before] = LiveReport.reports(state)
    assert before.acoustic_reason == :clock_uncertain
    state = observe(state, [{:provider_sample_mapping, g, 1_000, 100_000}])
    [after_mapping] = LiveReport.reports(state)
    assert after_mapping.durations_us.speech_end_to_provider_end == 30_000
    assert after_mapping.revision > before.revision

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:provider_sample_mapping, g, 1_001, 100_000})
  end

  test "mapping validates primitive types and integer bounds" do
    g = make_ref()

    for packet <- [
          {:provider_sample_mapping, "not-reference", 0, 0},
          {:provider_sample_mapping, g, -1, 0},
          {:provider_sample_mapping, g, 0, -1},
          {:provider_sample_mapping, g, 9_223_372_036_854_775_808, 0},
          {:provider_sample_mapping, g, 0, 9_223_372_036_854_775_808},
          {:provider_sample_mapping, g, 1.0, 0}
        ] do
      assert {:error, :invalid_evidence} = CapturePacket.charge(packet)
    end
  end

  test "link-first order also prevents a direct canonical claim" do
    {state, g, t} = base()
    other = make_ref()
    state = observe(state, [{:turn_link, g, t, g, other}])

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:room_turn_completed, g, t, "turn", "command", 71_000})
  end

  test "different provider turns cannot synthesize a commit-to-end duration" do
    {state, g, t} = base()
    p1 = make_ref()
    p2 = make_ref()
    inner = make_ref()

    state =
      observe(state, [
        {:turn_link, inner, p1, g, t},
        {:turn_link, inner, p2, g, t},
        {:provider_landmark, inner, p1, :provider_text_commit, 20_000, 512},
        {:provider_landmark, inner, p2, :provider_end_evidence, 30_000, 1_024},
        {:room_turn_completed, g, t, "turn", "command", 31_000}
      ])

    [report] = LiveReport.reports(state)
    assert report.provider_turn_id == nil
    assert report.durations_us.commit_to_provider_end == nil
  end
end
