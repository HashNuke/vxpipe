defmodule Vxpipe.Calls.TurnDiagnosticTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.TurnDiagnostic

  test "derives partial timing while retaining correlation identities" do
    assert {:ok, turn} = TurnDiagnostic.new(attributes())
    assert turn.durations_us.speech_end_to_provider_end == 400_000
    assert turn.durations_us.speech_end_to_first_audio == nil
    assert turn.metric_reasons.speech_end_to_first_audio == :missing_evidence
    assert turn.provider_turn_id == nil
    assert turn.revision == 1
  end

  test "rejects supplied durations, arbitrary payloads and unknown landmarks" do
    attrs = attributes()

    assert {:error, :invalid_turn_diagnostic} =
             TurnDiagnostic.new(Map.put(attrs, :durations_us, %{}))

    assert {:error, :invalid_turn_diagnostic} =
             TurnDiagnostic.new(Map.put(attrs, :transcript, "private"))

    assert {:error, :invalid_turn_diagnostic} =
             TurnDiagnostic.new(%{attrs | landmarks_us: %{unknown: 123}})
  end

  test "invalid acoustic evidence leaves nonacoustic stages useful" do
    attrs = attributes() |> Map.put(:acoustic_reason, :audio_gap)
    assert {:ok, turn} = TurnDiagnostic.new(attrs)
    assert turn.durations_us.speech_end_to_provider_end == nil
    assert turn.metric_reasons.speech_end_to_provider_end == :audio_gap
    assert turn.durations_us.provider_to_adapter == 10_000
    assert turn.quality == :incomplete
  end

  test "bounds identities, revision, uncertainty and sample metadata" do
    attrs = attributes()

    for invalid <- [
          Map.put(attrs, :revision, 0),
          Map.put(attrs, :uncertainty_us, -1),
          Map.put(attrs, :acoustic_sample, -1),
          %{attrs | clock_id: String.duplicate("x", 129)},
          %{attrs | turn_id: ""},
          %{attrs | landmarks_us: %{acoustic_end: 604_800_000_001}}
        ] do
      assert {:error, :invalid_turn_diagnostic} = TurnDiagnostic.new(invalid)
    end
  end

  defp attributes do
    %{
      run_id: "run-1",
      turn_id: "human-turn-1",
      stt_allocation_id: "allocation-1",
      clock_id: "clock-1",
      source_epoch: "source-1",
      landmarks_us: %{
        acoustic_end: 1_000_000,
        provider_end_received: 1_400_000,
        adapter_end_emitted: 1_410_000
      }
    }
  end
end
