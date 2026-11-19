defmodule Vxpipe.CallEngine.Diagnostics.LiveReportBoundaryCoverageTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "later uncertain evidence outside source coverage cannot invalidate an older complete turn" do
    state = base(11_264)
    [before] = LiveReport.reports(state)
    assert before.durations_us.speech_end_to_provider_end == 500_000

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 12_800, nil, 900_000, nil, :clock_uncertain}
      ])

    [after_later] = LiveReport.reports(state)
    assert after_later.durations_us.speech_end_to_provider_end == 500_000
  end

  test "an onset at the provider exclusive sample end belongs outside this turn" do
    state = base(11_264)

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 11_200, 700_000, 900_000, 1_000, nil}
      ])

    [report] = LiveReport.reports(state)
    assert report.durations_us.speech_end_to_provider_end == 500_000
  end

  test "a later endpoint beyond provider sample coverage cannot displace the covered endpoint" do
    state = base(13_312)

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 11_500, 600_000, 800_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 12_000, 650_000, 900_000, 1_000, nil}
      ])

    [report] = LiveReport.reports(state)
    assert report.acoustic_sample == 3_200
    assert [%{start_sample: 1_600, end_sample: 3_200}] = report.acoustic_segments.entries
    assert report.durations_us.speech_end_to_provider_end == 500_000
  end

  test "a same-epoch reuse failure permanently closes insufficient coverage" do
    state = base(10_752)
    state = observe(state, [{:reset, 0, :inference_failed, 900_000}])
    [report] = LiveReport.reports(state)
    assert report.acoustic_reason == :inference_reset
    assert report.durations_us.speech_end_to_provider_end == nil
  end

  test "later reset preserves a fully covered older turn" do
    state = base(11_264)
    [before] = LiveReport.reports(state)

    state =
      observe(state, [{:reset, 1, :audio_gap, 900_000}, {:acoustic_progress, 1, 12_000, 20_000}])

    assert LiveReport.reports(state) == [before]
  end

  test "new epoch progress does not fill old epoch coverage across a gap" do
    state = base(10_752)

    state =
      observe(state, [{:reset, 1, :audio_gap, 900_000}, {:acoustic_progress, 1, 12_000, 20_000}])

    [report] = LiveReport.reports(state)
    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.acoustic_sample == nil
    refute Map.has_key?(report.landmarks_us, :acoustic_end)
  end

  test "reset opening a fresh epoch before this turn does not retire its pending coverage" do
    generation = make_ref()
    previous = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      observe(state, [
        {:provider_sample_mapping, generation, 0, 0},
        {:reset, 1, :audio_gap, 900_000},
        {:provider_landmark, generation, previous, :provider_end_evidence, 1_000_000, 16_000},
        {:acoustic_boundary, 1, :speech_started, 17_600, 1_100_000, 1_200_000, 1_000, nil},
        {:acoustic_boundary, 1, :speech_ended, 19_200, 1_200_000, 1_300_000, 1_000, nil},
        {:acoustic_progress, 1, 16_000, 20_992},
        {:provider_landmark, generation, turn, :provider_end_evidence, 1_400_000, 22_400},
        {:room_turn_completed, generation, turn, "turn", "command", 1_410_000}
      ])

    [pending] = LiveReport.reports(state)
    assert pending.acoustic_reason == nil
    assert pending.durations_us.speech_end_to_provider_end == nil
    state = observe(state, [{:acoustic_progress, 1, 16_000, 22_528}])
    [complete] = LiveReport.reports(state)
    assert complete.durations_us.speech_end_to_provider_end == 200_000
  end

  test "uncertain evidence before the previous provider sample end does not poison the next turn" do
    generation = make_ref()
    previous = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      observe(state, [
        {:provider_sample_mapping, generation, 0, 0},
        {:provider_landmark, generation, previous, :provider_end_evidence, 700_000, 11_200},
        {:acoustic_boundary, 0, :speech_ended, 3_200, nil, 900_000, nil, :clock_uncertain},
        {:acoustic_boundary, 0, :speech_started, 12_800, 800_000, 950_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 16_000, 1_000_000, 1_100_000, 1_000, nil},
        {:acoustic_progress, 0, 0, 22_528},
        {:provider_landmark, generation, turn, :provider_end_evidence, 1_400_000, 22_400},
        {:room_turn_completed, generation, turn, "turn", "command", 1_410_000}
      ])

    [report] = LiveReport.reports(state)
    assert report.durations_us.speech_end_to_provider_end == 400_000
  end

  defp base(finalized) do
    generation = make_ref()
    turn = make_ref()

    LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})
    |> observe([
      {:provider_sample_mapping, generation, 0, 0},
      {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 3_200, 200_000, 300_000, 1_000, nil},
      {:acoustic_progress, 0, 0, finalized},
      {:provider_landmark, generation, turn, :provider_end_evidence, 700_000, 11_200},
      {:room_turn_completed, generation, turn, "turn", "command", 710_000}
    ])
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, current ->
      assert {:ok, next} = LiveReport.observe(current, packet)
      next
    end)
  end
end
