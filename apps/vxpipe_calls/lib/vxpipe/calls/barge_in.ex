defmodule Vxpipe.Calls.BargeIn do
  @moduledoc "Bounded, clock-scoped evidence of human onset to acknowledged server egress stop."

  @limit 32
  @maximum 604_800_000_000
  @identity_fields [
    :output_id,
    :agent_participant_id,
    :response_source_participant_id,
    :output_connection_id,
    :response_turn_id,
    :response_command_id
  ]
  @numeric_fields [
    :playback_started_us,
    :interruption_requested_us,
    :playback_stopped_us,
    :speech_started_us,
    :speech_start_confirmed_us,
    :speech_start_sample,
    :epoch,
    :uncertainty_us,
    :duration_us
  ]
  @fields @identity_fields ++ @numeric_fields ++ [:boundary, :reasons]
  @reasons [
    :not_playing,
    :stop_unavailable,
    :missing_evidence,
    :ambiguous_boundary,
    :clock_uncertain,
    :inference_reset,
    :audio_gap,
    :source_changed,
    :observer_overloaded,
    :before_run,
    :source_interval_unavailable
  ]

  def valid?(nil), do: true

  def valid?(%{version: 1, entries: entries, omitted_count: omitted, reasons: reasons} = evidence)
      when not is_struct(evidence) and map_size(evidence) == 4 and is_list(entries) and
             length(entries) <= @limit do
    count?(omitted) and reasons == if(omitted == 0, do: [], else: [:entry_limit]) and
      Enum.all?(entries, &entry?/1)
  end

  def valid?(_), do: false

  defp entry?(entry) when is_map(entry) and not is_struct(entry) do
    map_size(entry) == length(@fields) and Map.keys(entry) -- @fields == [] and
      Enum.all?(@identity_fields, &identifier?(Map.fetch!(entry, &1))) and
      Enum.all?(@numeric_fields, &optional_count?(Map.fetch!(entry, &1))) and
      entry.boundary == :server_egress and reasons?(entry.reasons) and evidence?(entry)
  end

  defp entry?(_), do: false

  defp evidence?(%{reasons: []} = entry) do
    Enum.all?(@numeric_fields, &(Map.fetch!(entry, &1) != nil)) and
      entry.playback_started_us <= entry.speech_started_us and
      entry.speech_started_us <= entry.interruption_requested_us and
      entry.interruption_requested_us <= entry.playback_stopped_us and
      entry.speech_started_us <= entry.speech_start_confirmed_us and
      entry.duration_us == entry.playback_stopped_us - entry.speech_started_us
  end

  defp evidence?(entry), do: entry.duration_us == nil

  defp reasons?(values) when is_list(values) and length(values) <= length(@reasons),
    do: Enum.all?(values, &(&1 in @reasons)) and Enum.uniq(values) == values

  defp reasons?(_), do: false
  defp count?(value), do: is_integer(value) and value in 0..@maximum
  defp optional_count?(nil), do: true
  defp optional_count?(value), do: count?(value)

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)
end
