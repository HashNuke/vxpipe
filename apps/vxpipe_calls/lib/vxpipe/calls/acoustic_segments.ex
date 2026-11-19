defmodule Vxpipe.Calls.AcousticSegments do
  @moduledoc "Versioned, bounded local speech segments in the enclosing source and clock."

  @limit 32
  @maximum 604_800_000_000
  @fields [
    :epoch,
    :start_sample,
    :end_sample,
    :start_us,
    :end_us,
    :start_confirmed_us,
    :end_confirmed_us,
    :uncertainty_us,
    :reasons
  ]
  @reasons [
    :partial_start,
    :audio_gap,
    :inference_reset,
    :source_changed,
    :clock_uncertain,
    :ambiguous_boundary,
    :observer_overloaded,
    :pending
  ]

  def valid?(nil), do: true

  def valid?(%{version: 1, entries: entries, omitted_count: omitted, reasons: reasons} = evidence)
      when map_size(evidence) == 4 and is_list(entries) and length(entries) <= @limit do
    count?(omitted) and reasons?(reasons, [:segment_limit | @reasons]) and
      (omitted == 0 or :segment_limit in reasons) and Enum.all?(entries, &segment?/1) and
      coherent?(entries)
  end

  def valid?(_), do: false

  defp coherent?(entries) do
    entries
    |> Enum.group_by(& &1.epoch)
    |> Enum.all?(fn {_epoch, segments} ->
      unique_boundary?(segments, :start_sample) and unique_boundary?(segments, :end_sample) and
        segments
        |> Enum.sort_by(&(&1.start_sample || -1))
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.all?(fn [previous, next] ->
          previous.end_sample != nil and next.start_sample != nil and
            previous.end_sample <= next.start_sample
        end)
    end)
  end

  defp unique_boundary?(segments, field) do
    values = segments |> Enum.map(&Map.fetch!(&1, field)) |> Enum.reject(&is_nil/1)
    length(Enum.uniq(values)) == length(values)
  end

  defp segment?(segment) when is_map(segment) and not is_struct(segment) do
    Map.keys(segment) -- @fields == [] and map_size(segment) == length(@fields) and
      count?(segment.epoch) and reasons?(segment.reasons, @reasons) and
      optional_count?(segment.uncertainty_us) and
      boundary?(segment.start_sample, segment.start_us, segment.start_confirmed_us) and
      boundary?(segment.end_sample, segment.end_us, segment.end_confirmed_us) and
      (segment.start_sample != nil or segment.end_sample != nil) and
      ordered?(segment.start_sample, segment.end_sample) and
      ordered?(segment.start_us, segment.end_us) and
      ordered?(segment.start_confirmed_us, segment.end_confirmed_us) and
      (segment.reasons != [] or complete?(segment))
  end

  defp segment?(_), do: false

  defp complete?(segment),
    do:
      Enum.all?(
        [:start_sample, :end_sample, :start_us, :end_us, :uncertainty_us],
        &(Map.fetch!(segment, &1) != nil)
      )

  defp boundary?(nil, nil, nil), do: true

  defp boundary?(sample, at, confirmed),
    do: count?(sample) and optional_count?(at) and count?(confirmed) and ordered?(at, confirmed)

  defp ordered?(nil, _), do: true
  defp ordered?(_, nil), do: true
  defp ordered?(first, last), do: first <= last
  defp count?(value), do: is_integer(value) and value in 0..@maximum
  defp optional_count?(nil), do: true
  defp optional_count?(value), do: count?(value)

  defp reasons?(values, allowed) when is_list(values) and length(values) <= length(allowed),
    do: Enum.all?(values, &(&1 in allowed)) and Enum.uniq(values) == values

  defp reasons?(_, _), do: false
end
