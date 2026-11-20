defmodule Vxpipe.Calls.TurnDiagnostic do
  @moduledoc "Bounded per-turn evidence with durations derived from clock-scoped landmarks."

  alias Vxpipe.CallEngine.Diagnostics.TurnTiming

  @identity_fields [:run_id, :turn_id, :stt_allocation_id, :clock_id, :source_epoch]
  @optional_identities [:provider_turn_id, :response_turn_id]
  @input_fields @identity_fields ++
                  @optional_identities ++
                  [
                    :revision,
                    :landmarks_us,
                    :acoustic_reason,
                    :acoustic_sample,
                    :uncertainty_us,
                    :acoustic_segments,
                    :barge_in
                  ]
  @enforce_keys @identity_fields ++ [:landmarks_us, :durations_us, :metric_reasons, :quality]
  @derive {Inspect, only: [:run_id, :turn_id, :revision, :quality]}
  defstruct @enforce_keys ++
              [
                acoustic_segments: nil,
                barge_in: nil,
                revision: 1,
                provider_turn_id: nil,
                response_turn_id: nil,
                acoustic_reason: nil,
                acoustic_sample: nil,
                uncertainty_us: nil
              ]

  def new(attributes) when is_map(attributes) and not is_struct(attributes) do
    with true <- Map.keys(attributes) -- @input_fields == [],
         true <- Enum.all?(@identity_fields, &identifier?(Map.get(attributes, &1))),
         true <- Enum.all?(@optional_identities, &optional_identifier?(Map.get(attributes, &1))),
         true <- byte_size(attributes.clock_id) <= 128,
         true <- valid_revision?(Map.get(attributes, :revision, 1)),
         true <- optional_count?(Map.get(attributes, :acoustic_sample)),
         true <- optional_count?(Map.get(attributes, :uncertainty_us)),
         true <- Vxpipe.Calls.AcousticSegments.valid?(Map.get(attributes, :acoustic_segments)),
         true <- Vxpipe.Calls.BargeIn.valid?(Map.get(attributes, :barge_in)),
         {:ok, timing} <- timing(attributes),
         report = TurnTiming.report(timing) do
      fields = Map.merge(attributes, Map.take(report, [:durations_us, :metric_reasons, :quality]))
      {:ok, struct!(__MODULE__, fields)}
    else
      _invalid -> {:error, :invalid_turn_diagnostic}
    end
  end

  def new(_attributes), do: {:error, :invalid_turn_diagnostic}

  defp timing(%{landmarks_us: landmarks, clock_id: clock_id} = attributes)
       when is_map(landmarks) and not is_struct(landmarks) and map_size(landmarks) <= 9 do
    initial = TurnTiming.new(clock_id)

    result =
      Enum.reduce_while(landmarks, {:ok, initial}, fn {kind, offset}, {:ok, timing} ->
        case TurnTiming.observe(timing, kind, offset, clock_id) do
          {:ok, next} -> {:cont, {:ok, next}}
          error -> {:halt, error}
        end
      end)

    with {:ok, timing} <- result do
      case Map.get(attributes, :acoustic_reason) do
        nil -> {:ok, timing}
        reason -> TurnTiming.invalidate_acoustic(timing, reason)
      end
    end
  end

  defp timing(_attributes), do: {:error, :invalid_landmarks}

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

  defp optional_identifier?(nil), do: true
  defp optional_identifier?(value), do: identifier?(value)
  defp valid_revision?(value), do: is_integer(value) and value in 1..9_223_372_036_854_775_807
  defp optional_count?(nil), do: true
  defp optional_count?(value), do: is_integer(value) and value in 0..604_800_000_000
end
