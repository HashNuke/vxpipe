defmodule Vxpipe.CallEngine.Diagnostics.LiveReportProgressTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "provider stages persist while acoustic coverage waits for the provider sample end" do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      observe(state, [
        {:provider_sample_mapping, generation, 0, 0},
        {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 3_200, 200_000, 300_000, 1_000, nil},
        {:acoustic_progress, 0, 0, 10_752},
        {:provider_landmark, generation, turn, :provider_end_evidence, 700_000, 11_200},
        {:room_turn_completed, generation, turn, "turn", "command", 710_000}
      ])

    [pending] = LiveReport.reports(state)
    assert pending.durations_us.provider_to_room == 10_000
    assert pending.durations_us.speech_end_to_provider_end == nil
    refute Map.has_key?(pending.landmarks_us, :acoustic_end)
    refute Map.has_key?(pending.landmarks_us, :observer_confirmed)

    state = observe(state, [{:acoustic_progress, 0, 0, 11_264}])
    [complete] = LiveReport.reports(state)
    assert complete.durations_us.speech_end_to_provider_end == 500_000
    assert complete.revision > pending.revision

    # Progress messages coalesce rather than consuming another retained slot.
    assert map_size(state.packets) == 6
    assert {:ok, ^state} = LiveReport.observe(state, {:acoustic_progress, 0, 0, 10_752})

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:acoustic_progress, 0, 512, 11_264})
  end

  test "a later epoch cannot fill an earlier gap or erase a covered earlier turn" do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    base = [
      {:provider_sample_mapping, generation, 0, 0},
      {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 3_200, 200_000, 300_000, 1_000, nil},
      {:provider_landmark, generation, turn, :provider_end_evidence, 700_000, 11_200},
      {:room_turn_completed, generation, turn, "turn", "command", 710_000}
    ]

    state = observe(state, base)
    pending = observe(state, [{:acoustic_progress, 0, 0, 10_752}])
    complete = observe(state, [{:acoustic_progress, 0, 0, 11_264}])
    later = [{:reset, 1, :audio_gap, 900_000}, {:acoustic_progress, 1, 12_000, 32_000}]
    retired = observe(pending, later)

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(retired, {:acoustic_progress, 0, 0, 11_264})

    [missing] = LiveReport.reports(retired)
    assert missing.durations_us.speech_end_to_provider_end == nil
    assert missing.acoustic_reason == :audio_gap
    [covered] = complete |> observe(later) |> LiveReport.reports()
    assert covered.durations_us.speech_end_to_provider_end == 500_000
  end

  test "speech beginning at the provider's exclusive sample end belongs to later audio" do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      observe(state, [
        {:provider_sample_mapping, generation, 0, 0},
        {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 3_200, 200_000, 300_000, 1_000, nil},
        {:acoustic_progress, 0, 0, 11_264},
        {:provider_landmark, generation, turn, :provider_end_evidence, 800_000, 11_264},
        {:room_turn_completed, generation, turn, "turn", "command", 810_000}
      ])

    [before] = LiveReport.reports(state)
    assert before.durations_us.speech_end_to_provider_end == 600_000

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 11_264, 704_000, 900_000, 1_000, nil},
        {:acoustic_progress, 0, 0, 13_312}
      ])

    assert LiveReport.reports(state) == [before]
  end

  test "a reset opening a new epoch does not retire that epoch's pending coverage" do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      observe(state, [
        {:provider_sample_mapping, generation, 0, 0},
        {:reset, 1, :audio_gap, 50_000},
        {:acoustic_boundary, 1, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
        {:acoustic_boundary, 1, :speech_ended, 3_200, 200_000, 300_000, 1_000, nil},
        {:acoustic_progress, 1, 1_600, 10_752},
        {:provider_landmark, generation, turn, :provider_end_evidence, 700_000, 11_200},
        {:room_turn_completed, generation, turn, "turn", "command", 710_000}
      ])

    # The gap belongs to the previous provider turn.
    prior = make_ref()

    state =
      observe(state, [
        {:provider_landmark, generation, prior, :provider_end_evidence, 60_000, 960}
      ])

    [pending] = LiveReport.reports(state)
    assert pending.acoustic_reason == nil
    assert {:ok, duplicate} = LiveReport.observe(state, {:reset, 1, :audio_gap, 50_000})
    assert duplicate == state
    assert pending.durations_us.speech_end_to_provider_end == nil
    state = observe(state, [{:acoustic_progress, 1, 1_600, 11_264}])
    [complete] = LiveReport.reports(state)
    assert complete.durations_us.speech_end_to_provider_end == 500_000
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, current ->
      assert {:ok, next} = LiveReport.observe(current, packet)
      next
    end)
  end
end
