defmodule Vxpipe.Console.TelemetryReporter.StartupProjection do
  @moduledoc false

  @progress [:vxpipe, :call_engine, :startup, :progress]
  @stop [:vxpipe, :call_engine, :startup, :stop]
  @events [@progress, @stop]
  @outcomes [:ready, :failed, :timeout, :disconnected]
  @blockers [
    :speech_to_text,
    :text_to_speech,
    :model_inference,
    :tools,
    :recording,
    :room_services,
    :media,
    :opening_audio,
    :other
  ]

  def events, do: @events
  def new, do: %{stops: %{}, blockers: %{}, terminal_blockers: %{}}

  def sanitize(@progress, measurements, metadata),
    do: {:ok, sanitize_counted_duration(measurements), %{blockers: blockers(metadata)}}

  def sanitize(@stop, measurements, metadata),
    do:
      {:ok, sanitize_counted_duration(measurements),
       %{
         outcome: normalize(metadata, :outcome, @outcomes, :unknown),
         blockers: blockers(metadata)
       }}

  def sanitize(_event, _measurements, _metadata), do: :unhandled

  def project(@progress, %{count: 1, duration: duration}, %{blockers: blockers}, state)
      when is_integer(duration) and duration >= 0 do
    counts = Enum.reduce(blockers, state.blockers, &Map.update(&2, &1, 1, fn n -> n + 1 end))
    {:ok, %{state | blockers: counts}}
  end

  def project(
        @stop,
        %{count: 1, duration: duration},
        %{outcome: outcome, blockers: blockers},
        state
      )
      when is_integer(duration) and duration >= 0 do
    terminal =
      Enum.reduce(
        blockers,
        state.terminal_blockers,
        &Map.update(&2, {outcome, &1}, 1, fn n -> n + 1 end)
      )

    {:ok,
     %{
       state
       | stops: update_duration(state.stops, outcome, duration),
         terminal_blockers: terminal
     }}
  end

  def project(_event, _measurements, _metadata, _state), do: :unhandled

  defp blockers(%{blockers: values}) when is_list(values) do
    values
    |> Enum.take(64)
    |> Enum.map(fn kind -> if kind in @blockers, do: kind, else: :other end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp blockers(_metadata), do: []

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
