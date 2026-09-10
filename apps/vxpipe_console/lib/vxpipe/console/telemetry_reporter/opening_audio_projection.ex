defmodule Vxpipe.Console.TelemetryReporter.OpeningAudioProjection do
  @moduledoc false

  @stop [:vxpipe, :call_engine, :opening_audio, :stop]
  @events [@stop]
  @sources [:text, :file_url]
  @outcomes [:completed, :failed]

  @spec events() :: [nonempty_list(atom())]
  def events, do: @events

  @spec new() :: map()
  def new, do: %{stops: %{}}

  @spec sanitize([atom()], map(), map()) :: {:ok, map(), map()} | :unhandled
  def sanitize(@stop, measurements, metadata) do
    {
      :ok,
      sanitize_counted_duration(measurements),
      %{
        source: normalize(metadata, :source, @sources, :unknown),
        outcome: normalize(metadata, :outcome, @outcomes, :unknown)
      }
    }
  end

  def sanitize(_event, _measurements, _metadata), do: :unhandled

  @spec project([atom()], map(), map(), map()) :: {:ok, map()} | :unhandled
  def project(
        @stop,
        %{count: 1, duration: duration},
        %{source: source, outcome: outcome},
        projection
      )
      when is_integer(duration) and duration >= 0 do
    {:ok,
     %{
       projection
       | stops: update_duration(projection.stops, {source, outcome}, duration)
     }}
  end

  def project(event, _measurements, _metadata, _projection) when event in @events,
    do: :unhandled

  def project(_event, _measurements, _metadata, _projection), do: :unhandled

  defp sanitize_counted_duration(%{count: 1, duration: duration})
       when is_integer(duration) and duration >= 0,
       do: %{count: 1, duration: duration}

  defp sanitize_counted_duration(_measurements), do: %{}

  defp normalize(metadata, key, allowed, fallback) when is_map(metadata) do
    value = Map.get(metadata, key)
    if value in allowed, do: value, else: fallback
  end

  defp normalize(_metadata, _key, _allowed, fallback), do: fallback

  defp update_duration(aggregates, key, native_duration) do
    duration_us = System.convert_time_unit(native_duration, :native, :microsecond)

    Map.update(
      aggregates,
      key,
      duration_stats(duration_us),
      &%{
        count: &1.count + 1,
        total_us: &1.total_us + duration_us,
        minimum_us: min(&1.minimum_us, duration_us),
        maximum_us: max(&1.maximum_us, duration_us),
        latest_us: duration_us
      }
    )
  end

  defp duration_stats(duration_us) do
    %{
      count: 1,
      total_us: duration_us,
      minimum_us: duration_us,
      maximum_us: duration_us,
      latest_us: duration_us
    }
  end
end
