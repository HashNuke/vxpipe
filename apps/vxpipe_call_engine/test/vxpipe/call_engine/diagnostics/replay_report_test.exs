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
