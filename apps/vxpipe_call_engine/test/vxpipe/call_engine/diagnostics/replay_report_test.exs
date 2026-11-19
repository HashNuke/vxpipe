defmodule Vxpipe.CallEngine.Diagnostics.ReplayReportTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.ReplayReport

  test "uses the final correlated speech boundary even when confirmation follows provider end" do
    trace = %{
      events: [endpoint(100_000, 612_000), onset(200_000), endpoint(300_000, 812_000)],
      notices: []
    }

    assert {:ok, [report]} =
             ReplayReport.build("clock", "source", [%{provider_end_received: 600_000}], trace)

    assert report.durations_us.speech_end_to_provider_end == 300_000
    assert report.durations_us.observer_confirmation == 512_000
    assert report.acoustic_sample == 4_800
  end

  test "speech resumption before provider end makes an older pause ambiguous" do
    trace = %{events: [endpoint(100_000, 612_000), onset(200_000)], notices: []}

    assert {:ok, [report]} =
             ReplayReport.build("clock", "source", [%{provider_end_received: 600_000}], trace)

    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.acoustic_reason == :ambiguous_boundary
  end

  test "missing audio preserves useful provider timing while invalidating acoustic metrics" do
    trace = %{events: [endpoint(100_000, 612_000)], notices: [:audio_gap]}

    assert {:ok, [report]} =
             ReplayReport.build(
               "clock",
               "source",
               [%{provider_end_received: 400_000, adapter_end_emitted: 410_000}],
               trace
             )

    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.durations_us.provider_to_adapter == 10_000
    assert report.acoustic_reason == :audio_gap
  end

  test "a boundary from another clock or source cannot enter the report" do
    {:speech_ended, position} = endpoint(100_000, 612_000)

    for invalid <- [%{position | clock_id: "foreign"}, %{position | source_epoch: "foreign"}] do
      assert {:error, :invalid_replay_evidence} =
               ReplayReport.build("clock", "source", [%{provider_end_received: 400_000}], %{
                 events: [{:speech_ended, invalid}],
                 notices: []
               })
    end
  end

  test "explicit sample intervals retain multiple segments and unattached speech" do
    trace = segment_trace()

    assert {:ok, %{turns: [report], unattached_segments: unattached}} =
             ReplayReport.build("clock", "source", [%{provider_end_received: 500_000}], trace, [
               {0, 640}
             ])

    assert [%{start_sample: 0, end_sample: 160}, %{start_sample: 320, end_sample: 480}] =
             report.acoustic_segments.entries

    assert [%{start_sample: 800, end_sample: 960}] = unattached.entries

    assert {:ok, %{turns: [missing], unattached_segments: %{entries: [_, _, _]}}} =
             ReplayReport.build("clock", "source", [%{provider_end_received: 500_000}], trace, [
               nil
             ])

    assert missing.acoustic_segments.entries == []
    assert missing.acoustic_segments.reasons == [:pending]
  end

  test "segment replay rejects foreign provenance, malformed intervals and non-acoustic packets" do
    trace = segment_trace()

    for invalid <- [
          put_in(trace, [:segment_evidence, :clock_id], "foreign"),
          put_in(trace, [:segment_evidence, :source_epoch], "foreign"),
          put_in(trace, [:segment_evidence, :packets], [
            {:room_turn_completed, make_ref(), make_ref(), "x", "y", 0}
          ])
        ] do
      assert {:error, :invalid_replay_evidence} =
               ReplayReport.build("clock", "source", [%{}], invalid, [{0, 640}])
    end

    for intervals <- [[], [{640, 0}], [{-1, 640}]] do
      assert {:error, :invalid_replay_evidence} =
               ReplayReport.build("clock", "source", [%{}], trace, intervals)
    end
  end

  test "scalar replay uses the same proven segment interval and finalized coverage" do
    trace = segment_trace()

    assert {:ok, %{turns: [report]}} =
             ReplayReport.build("clock", "source", [%{provider_end_received: 500_000}], trace, [
               {0, 640}
             ])

    assert report.acoustic_sample == 480
    assert report.durations_us.speech_end_to_provider_end == 471_200

    pending =
      update_in(trace.segment_evidence.packets, fn packets ->
        Enum.map(packets, fn
          {:acoustic_progress, 0, 0, _} -> {:acoustic_progress, 0, 0, 512}
          packet -> packet
        end)
      end)

    assert {:ok, %{turns: [report]}} =
             ReplayReport.build("clock", "source", [%{provider_end_received: 500_000}], pending, [
               {0, 640}
             ])

    assert report.acoustic_sample == nil
    assert report.durations_us.speech_end_to_provider_end == nil
  end

  defp segment_trace do
    packets =
      for {kind, sample} <- [
            {:speech_started, 0},
            {:speech_ended, 160},
            {:speech_started, 320},
            {:speech_ended, 480},
            {:speech_started, 800},
            {:speech_ended, 960}
          ] do
        {:acoustic_boundary, 0, kind, sample, sample * 60, sample * 60 + 100, 10, nil}
      end

    %{
      events: [],
      notices: [],
      segment_evidence: %{
        clock_id: "clock",
        source_epoch: "source",
        packets: packets ++ [{:acoustic_progress, 0, 0, 1_024}]
      }
    }
  end

  defp endpoint(offset, confirmed),
    do:
      {:speech_ended,
       %{
         clock_id: "clock",
         source_epoch: "source",
         sample: div(offset * 16_000, 1_000_000),
         offset_us: offset,
         confirmed_offset_us: confirmed,
         uncertainty_us: 1_000
       }}

  defp onset(offset) do
    {:speech_ended, position} = endpoint(offset, offset + 128_000)
    {:speech_started, position}
  end
end
