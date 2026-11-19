defmodule Vxpipe.CallEngine.Diagnostics.LiveReportTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  setup do
    generation = make_ref()
    turn = make_ref()
    context = %{generation: generation, clock_id: "clock", origin_us: -100_000}

    {:ok, state} =
      LiveReport.observe(LiveReport.new(context), {:provider_sample_mapping, generation, 0, 0})

    %{state: state, generation: generation, turn: turn}
  end

  test "joins provider, accepted room and response evidence by identity, with run offsets", c do
    packets = [
      {:provider_landmark, c.generation, c.turn, :provider_text_commit, -80_000, 1_000},
      {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -70_000, 2_000},
      {:provider_landmark, c.generation, c.turn, :adapter_end_emission, -69_000, 2_000},
      {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000},
      {:response_landmark, "turn", "command", "text", :first_response_text, -60_000},
      {:response_landmark, "turn", "command", "audio", :first_audio_start, -50_000}
    ]

    state = observe(c.state, packets)
    [report] = LiveReport.reports(state)
    assert report.turn_id == "turn"
    assert report.landmarks_us.provider_end_received == 30_000
    assert report.durations_us.provider_to_room == 2_000
    assert report.durations_us.text_to_first_audio == 10_000
    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.provider_turn_id != nil
    assert report.stt_allocation_id != nil
  end

  test "late wrapper links join earlier evidence, while unrelated output is never borrowed", c do
    inner = make_ref()
    inner_turn = make_ref()

    packets = [
      {:provider_landmark, inner, inner_turn, :provider_end_evidence, -70_000, 2_000},
      {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000},
      {:response_landmark, "turn", "other-command", "output", :first_response_text, -60_000}
    ]

    state = observe(c.state, packets)
    [before] = LiveReport.reports(state)
    refute Map.has_key?(before.landmarks_us, :provider_end_received)
    state = observe(state, [{:turn_link, inner, inner_turn, c.generation, c.turn}])
    [after_link] = LiveReport.reports(state)
    assert after_link.landmarks_us.provider_end_received == 30_000
    refute Map.has_key?(after_link.landmarks_us, :first_response_text)
    assert after_link.revision > before.revision
    assert LiveReport.reports(observe(state, packets)) == [after_link]
  end

  test "a late confirmed endpoint updates the same row, separating boundary and confirmation",
       c do
    state =
      observe(c.state, [
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -30_000, 3_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -29_000}
      ])

    [before] = LiveReport.reports(state)

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 90_000, 1_000, nil},
        {:acoustic_progress, 0, 0, 3_072}
      ])

    [report] = LiveReport.reports(state)
    assert report.turn_id == before.turn_id
    assert report.revision > before.revision
    assert report.durations_us.speech_end_to_provider_end == 30_000
    assert report.durations_us.observer_confirmation == 50_000
    assert report.acoustic_sample == 512
  end

  test "resumed speech and reset gaps invalidate acoustic estimates without losing provider stages",
       c do
    base = [
      {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 50_000, 1_000, nil},
      {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -30_000, 3_000},
      {:room_turn_completed, c.generation, c.turn, "turn", "command", -29_000}
    ]

    state = observe(c.state, base)

    resumed =
      observe(state, [{:acoustic_boundary, 0, :speech_started, 1_024, 60_000, 65_000, 1_000, nil}])

    [report] = LiveReport.reports(resumed)
    assert report.acoustic_reason == :ambiguous_boundary
    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.durations_us.provider_to_room == 1_000
    reset = observe(state, [{:reset, 1, :audio_gap, -45_000}])
    assert [%{acoustic_reason: :audio_gap}] = LiveReport.reports(reset)
  end

  test "capacity bounds retained evidence and rejects invalid or conflicting identities", c do
    limited =
      LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000},
        maximum_packets: 1
      )

    packet = {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}
    state = observe(limited, [packet, packet])

    assert {:error, :full} =
             LiveReport.observe(
               state,
               {:response_landmark, "turn", "command", "out", :first_response_text, -60_000}
             )

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(
               state,
               {:room_turn_completed, c.generation, c.turn, "other", "command", -68_000}
             )

    assert {:error, :invalid_evidence} = LiveReport.observe(state, {:audio, "not timing"})

    assert {:error, :foreign_generation} =
             LiveReport.observe(
               c.state,
               {:room_turn_completed, make_ref(), c.turn, "turn", "command", -68_000}
             )

    bytes =
      LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000},
        maximum_bytes: 1
      )

    assert {:error, :full} = LiveReport.observe(bytes, packet)
  end

  test "an unaccepted earlier provider turn cannot donate its endpoint to a later room turn", c do
    earlier = make_ref()

    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 20_000, 25_000, 1_000, nil},
        {:provider_landmark, c.generation, earlier, :provider_end_evidence, -70_000, 2_000},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -30_000, 3_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -29_000}
      ])

    assert [%{durations_us: %{speech_end_to_provider_end: nil}}] = LiveReport.reports(state)
  end

  test "two canonical turns cannot share an accepted room identity", c do
    state =
      observe(c.state, [{:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}])

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(
               state,
               {:room_turn_completed, c.generation, make_ref(), "turn", "other", -60_000}
             )
  end

  test "provider turns with indistinguishable endpoints do not claim the same acoustic estimate",
       c do
    other = make_ref()

    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 20_000, 25_000, 1_000, nil},
        {:provider_landmark, c.generation, other, :provider_end_evidence, -70_000, 2_000},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -70_000, 2_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}
      ])

    assert [
             %{
               acoustic_reason: :ambiguous_boundary,
               durations_us: %{speech_end_to_provider_end: nil}
             }
           ] = LiveReport.reports(state)
  end

  test "missing provider-to-source sample alignment never yields an available acoustic duration",
       c do
    state = LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000})

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 20_000, 25_000, 1_000, nil},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -70_000, 2_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}
      ])

    assert [
             %{
               acoustic_reason: :clock_uncertain,
               durations_us: %{speech_end_to_provider_end: nil}
             }
           ] = LiveReport.reports(state)
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, state ->
      assert {:ok, next} = LiveReport.observe(state, packet)
      next
    end)
  end
end
