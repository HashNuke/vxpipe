defmodule Vxpipe.CallEngine.Diagnostics.LiveReportRegressionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, acc ->
      assert {:ok, next} = LiveReport.observe(acc, packet)
      next
    end)
  end

  defp base do
    generation = make_ref()
    turn = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})
    {:ok, state} = LiveReport.observe(state, {:provider_sample_mapping, generation, 0, 0})
    {state, generation, turn}
  end

  test "retained response keys detach large backing binaries" do
    {state, _, _} = base()
    backing = :crypto.strong_rand_bytes(4_000_000)
    turn = binary_part(backing, 0, 200)
    command = binary_part(backing, 200, 200)
    assert :binary.referenced_byte_size(turn) == 4_000_000

    {:ok, state} =
      LiveReport.observe(
        state,
        {:response_landmark, turn, command, "out", :first_response_text, 40_000}
      )

    [{:response, retained_turn, retained_command, _}] =
      Enum.filter(Map.keys(state.packets), &match?({:response, _, _, _}, &1))

    assert :binary.referenced_byte_size(retained_turn) == byte_size(retained_turn)
    assert :binary.referenced_byte_size(retained_command) == byte_size(retained_command)
  end

  test "late unmapped resumed speech does not leave the earlier endpoint available" do
    {state, g, t} = base()

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 50_000, 1_000, nil},
        {:provider_landmark, g, t, :provider_end_evidence, 70_000, 3_000},
        {:room_turn_completed, g, t, "turn", "command", 71_000}
      ])

    [before] = LiveReport.reports(state)
    assert before.durations_us.speech_end_to_provider_end == 30_000

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 1_024, nil, 90_000, nil, :unobserved_audio}
      ])

    [after_late] = LiveReport.reports(state)
    assert after_late.durations_us.speech_end_to_provider_end == nil
    assert after_late.revision > before.revision
  end

  test "a boundary beyond the provider accepted sample coverage is unavailable" do
    {state, g, t} = base()

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 1_024, 40_000, 50_000, 1_000, nil},
        {:provider_landmark, g, t, :provider_end_evidence, 70_000, 512},
        {:room_turn_completed, g, t, "turn", "command", 71_000}
      ])

    [report] = LiveReport.reports(state)
    assert report.durations_us.speech_end_to_provider_end == nil
  end

  test "direct and linked canonical turns do not reuse the same provider turn" do
    {state, g, t} = base()
    other = make_ref()

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 50_000, 1_000, nil},
        {:provider_landmark, g, t, :provider_end_evidence, 70_000, 3_000},
        {:room_turn_completed, g, t, "turn-1", "command-1", 71_000},
        {:room_turn_completed, g, other, "turn-2", "command-2", 72_000}
      ])

    case LiveReport.observe(state, {:turn_link, g, t, g, other}) do
      {:error, :conflicting_evidence} ->
        :ok

      {:ok, state} ->
        reports = LiveReport.reports(state)
        assert Enum.all?(reports, &is_nil(&1.durations_us.speech_end_to_provider_end))
    end
  end
end
