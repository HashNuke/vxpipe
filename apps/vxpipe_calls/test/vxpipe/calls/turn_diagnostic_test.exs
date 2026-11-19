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

  test "retains multiple acoustic segments without treating each pause as a turn" do
    segments = %{
      version: 1,
      entries: [segment(0, 100), segment(200, 300)],
      omitted_count: 0,
      reasons: []
    }

    assert {:ok, turn} = TurnDiagnostic.new(Map.put(attributes(), :acoustic_segments, segments))
    assert turn.acoustic_segments == segments
    assert turn.turn_id == "human-turn-1"
    assert {:ok, legacy} = TurnDiagnostic.new(attributes())
    assert legacy.acoustic_segments == nil
  end

  test "rejects unbounded, contradictory or private segment evidence" do
    valid = %{version: 1, entries: [segment(0, 100)], omitted_count: 0, reasons: []}

    for invalid <- [
          %{valid | version: 2},
          %{valid | entries: List.duplicate(segment(0, 100), 33)},
          %{valid | entries: [Map.put(segment(0, 100), :audio, "private")]},
          %{valid | entries: [segment(100, 0)]},
          %{valid | entries: [Map.put(segment(0, 100), :start_confirmed_us, 600_000)]},
          %{valid | entries: [segment(0, 100), segment(0, 100)]},
          %{valid | entries: [segment(0, 100), segment(50, 150)]},
          %{
            valid
            | entries: [
                %{
                  segment(0, 100)
                  | end_sample: nil,
                    end_us: nil,
                    end_confirmed_us: nil,
                    reasons: [:pending]
                },
                segment(0, 100)
              ]
          },
          %{valid | omitted_count: -1},
          %{valid | reasons: [:unknown]},
          %{valid | omitted_count: 1}
        ] do
      assert {:error, :invalid_turn_diagnostic} =
               TurnDiagnostic.new(Map.put(attributes(), :acoustic_segments, invalid))
    end
  end

  test "distinct inference epochs may reuse sample positions" do
    evidence = %{
      version: 1,
      entries: [segment(0, 100), %{segment(0, 100) | epoch: 1}],
      omitted_count: 0,
      reasons: []
    }

    assert {:ok, _} = TurnDiagnostic.new(Map.put(attributes(), :acoustic_segments, evidence))
  end

  test "segment truncation is explicit and does not invent missing endpoints" do
    partial = %{
      segment(0, 100)
      | end_sample: nil,
        end_us: nil,
        end_confirmed_us: nil,
        reasons: [:audio_gap]
    }

    evidence = %{version: 1, entries: [partial], omitted_count: 2, reasons: [:segment_limit]}
    assert {:ok, turn} = TurnDiagnostic.new(Map.put(attributes(), :acoustic_segments, evidence))
    assert turn.acoustic_segments == evidence
  end

  defp segment(first, last) do
    %{
      epoch: 0,
      start_sample: first,
      end_sample: last,
      start_us: first * 100,
      end_us: last * 100,
      start_confirmed_us: first * 100 + 1_000,
      end_confirmed_us: last * 100 + 512_000,
      uncertainty_us: 100,
      reasons: []
    }
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
