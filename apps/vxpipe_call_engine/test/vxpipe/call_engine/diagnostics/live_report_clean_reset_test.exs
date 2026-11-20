defmodule Vxpipe.CallEngine.Diagnostics.LiveReportCleanResetTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "clean operational turn settlement preserves completed endpoint and barge-in evidence" do
    state = report(:provider_turn_settled)
    [row] = LiveReport.reports(state)
    assert row.acoustic_reason == nil
    assert row.durations_us.speech_end_to_provider_end == 500_000
    assert [%{duration_us: 650_000, reasons: []}] = row.barge_in.entries
  end

  test "clean settlement during interruption preserves onset to acknowledged stop" do
    [row] = report(:provider_turn_settled) |> LiveReport.reports()
    assert [%{duration_us: 650_000, reasons: []}] = row.barge_in.entries
  end

  for reason <- [:inference_failed, :audio_gap, :source_replaced] do
    test "actual #{reason} still invalidates affected timing" do
      [row] = report(unquote(reason)) |> LiveReport.reports()
      assert row.durations_us.speech_end_to_provider_end == nil
      assert [%{duration_us: nil}] = row.barge_in.entries
    end
  end

  test "clean settlement closes incomplete coverage without fabricating an endpoint" do
    state = report(:provider_turn_settled, 10_752)
    [row] = LiveReport.reports(state)
    assert row.durations_us.speech_end_to_provider_end == nil
    assert row.acoustic_sample == nil
    refute Map.has_key?(row.landmarks_us, :acoustic_end)

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:acoustic_progress, 0, 0, 11_264})
  end

  test "clean settlement cannot create missing onset or endpoint evidence" do
    for kind <- [:speech_started, :speech_ended] do
      [row] = report(:provider_turn_settled, 11_264, kind) |> LiveReport.reports()
      assert row.durations_us.speech_end_to_provider_end == nil
      if kind == :speech_started, do: assert([%{duration_us: nil}] = row.barge_in.entries)
    end
  end

  defp report(reason, finalized \\ 11_264, omit \\ nil) do
    generation = make_ref()
    reference = make_ref()
    output = {"agent", "human", "connection", "old-turn", "old-command", "output"}

    packets = [
      {:provider_sample_mapping, generation, 0, 0},
      {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 3_200, 200_000, 300_000, 1_000, nil},
      {:acoustic_progress, 0, 0, finalized},
      {:provider_landmark, generation, reference, :provider_end_evidence, 700_000, 11_200},
      {:room_turn_completed, generation, reference, "turn", "command", 710_000},
      {:barge_in_playback, generation, reference, "turn", "command", output, 50_000, 700_000,
       750_000, nil},
      {:reset, 1, reason, 700_000}
    ]

    packets = Enum.reject(packets, &match?({:acoustic_boundary, _, ^omit, _, _, _, _, _}, &1))

    Enum.reduce(
      packets,
      LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0}),
      fn packet, state ->
        assert {:ok, next} = LiveReport.observe(state, packet)
        next
      end
    )
  end
end
