defmodule Vxpipe.Console.TelemetryReporter.TransferProjection do
  @moduledoc false

  @worker [:vxpipe, :call_engine, :transfer, :worker, :stop]
  @pressure [:vxpipe, :call_engine, :wait_sounds, :pressure]
  @drop [:vxpipe, :gateway, :audio_output, :drop]

  def events, do: [@worker, @pressure, @drop]
  def new, do: %{workers: %{}, playback: %{}, output_drops: %{}}

  def sanitize(@worker, measurements, metadata) do
    {:ok, count(measurements),
     %{outcome: category(metadata, :outcome, [:cancelled, :unexpected])}}
  end

  def sanitize(@pressure, measurements, metadata) do
    {:ok, pressure(measurements),
     %{
       kind: category(metadata, :kind, [:wait, :cue]),
       status:
         category(metadata, :status, [:queued, :draining, :paused, :stopped, :completed, :failed])
     }}
  end

  def sanitize(@drop, measurements, metadata) do
    {:ok, count(measurements),
     %{
       source: category(metadata, :source, [:room, :direct]),
       reason:
         category(metadata, :reason, [
           :busy,
           :held,
           :cleared,
           :clearing,
           :stale,
           :invalid,
           :unavailable
         ])
     }}
  end

  def sanitize(_event, _measurements, _metadata), do: :unhandled

  def project(@worker, %{count: 1}, %{outcome: outcome}, state),
    do: {:ok, update_in(state.workers, &increment(&1, outcome))}

  def project(@drop, %{count: 1}, %{source: source, reason: reason}, state),
    do: {:ok, update_in(state.output_drops, &increment(&1, {source, reason}))}

  def project(
        @pressure,
        %{count: 1, depth: depth, limit: limit},
        %{kind: kind, status: status},
        state
      ) do
    samples =
      Map.update(
        state.playback,
        {kind, status},
        %{count: 1, max_depth: depth, max_limit: limit},
        fn sample ->
          %{
            count: sample.count + 1,
            max_depth: max(sample.max_depth, depth),
            max_limit: max(sample.max_limit, limit)
          }
        end
      )

    {:ok, %{state | playback: samples}}
  end

  def project(_event, _measurements, _metadata, _state), do: :unhandled

  defp count(%{count: 1}), do: %{count: 1}
  defp count(_measurements), do: %{}

  defp pressure(%{count: 1, depth: depth, limit: limit})
       when is_integer(depth) and is_integer(limit) and depth >= 0 and depth <= limit and
              limit > 0,
       do: %{count: 1, depth: depth, limit: limit}

  defp pressure(_measurements), do: %{}

  defp category(metadata, key, allowed) when is_map(metadata) do
    value = Map.get(metadata, key)
    if value in allowed, do: value, else: :unknown
  end

  defp category(_metadata, _key, _allowed), do: :unknown

  defp increment(counts, key), do: Map.update(counts, key, 1, &(&1 + 1))
end
