defmodule Vxpipe.Persistence.LatencyRecordCodec do
  @moduledoc false
  alias Vxpipe.Calls.{LatencyRun, TurnDiagnostic}

  @derived [:durations_us, :metric_reasons, :quality]
  @keys Map.keys(LatencyRun.__struct__()) ++
          Map.keys(TurnDiagnostic.__struct__()) ++
          [
            :provider,
            :model,
            :commit_strategy,
            :inference_source,
            :vad_model,
            :algorithm_version,
            :sample_rate,
            :onset_threshold,
            :offset_threshold,
            :onset_frames,
            :offset_frames,
            :observed_turns,
            :dropped_audio_frames,
            :unmatched_provider_events,
            :acoustic_end,
            :observer_confirmed,
            :provider_text_commit,
            :provider_end_received,
            :adapter_end_emitted,
            :room_turn_completed,
            :first_response_text,
            :first_audio_started,
            :manual_commit_sent
          ]
  @key_lookup Map.new(@keys, &{Atom.to_string(&1), &1})
  @enums [
    :running,
    :closed,
    :incomplete,
    :manual,
    :vad,
    :provider_semantic,
    :unknown,
    :operational_reuse,
    :benchmark_only,
    :audio_gap,
    :ambiguous_boundary,
    :observer_overloaded,
    :source_changed,
    :partial_start,
    :inference_reset,
    :clock_uncertain,
    :observer_unavailable,
    :unsupported,
    :policy_denied,
    :storage_loss,
    :disabled,
    :call_ended,
    :lease_expired
  ]
  @enum_lookup Map.new(@enums, &{Atom.to_string(&1), &1})

  def encode(%LatencyRun{} = run), do: run |> Map.from_struct() |> json()

  def encode(%TurnDiagnostic{} = turn),
    do: turn |> Map.from_struct() |> Map.drop(@derived) |> json()

  def decode_run(record), do: decode(record, &LatencyRun.new/1)
  def decode_turn(record), do: decode(record, &TurnDiagnostic.new/1)

  defp decode(record, constructor) do
    constructor.(decode_map(record))
  rescue
    _error -> {:error, :invalid_diagnostic_record}
  end

  defp decode_map(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {key, value} ->
      atom = Map.fetch!(@key_lookup, key)
      {atom, decode_value(atom, value)}
    end)
  end

  defp decode_value(key, value)
       when key in [:anchor_utc, :heartbeat_at, :closed_at] and not is_nil(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    datetime
  end

  defp decode_value(key, value)
       when key in [:state, :commit_strategy, :inference_source, :acoustic_reason] and
              not is_nil(value),
       do: Map.fetch!(@enum_lookup, value)

  defp decode_value(:reasons, values), do: Enum.map(values, &Map.fetch!(@enum_lookup, &1))
  defp decode_value(_key, value) when is_map(value), do: decode_map(value)
  defp decode_value(_key, value), do: value

  defp json(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp json(value) when is_map(value),
    do: Map.new(value, fn {key, entry} -> {Atom.to_string(key), json(entry)} end)

  defp json(value) when is_list(value), do: Enum.map(value, &json/1)
  defp json(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp json(value), do: value
end
