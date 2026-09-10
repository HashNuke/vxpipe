defmodule Vxpipe.Console.TelemetryReporter.MCPProjection do
  @moduledoc false

  @connection_stop [:vxpipe, :mcp, :connection, :stop]
  @request_stop [:vxpipe, :mcp, :request, :stop]
  @events [@connection_stop, @request_stop]
  @connection_operations [:open, :close]
  @connection_outcomes [:opened, :reused, :failed, :closed, :absent]
  @request_operations [:discovery, :invocation]
  @request_outcomes [
    :ok,
    :failed,
    :timeout,
    :rejected,
    :too_large,
    :not_submitted,
    :remote_error,
    :unknown
  ]

  @spec events() :: [nonempty_list(atom())]
  def events, do: @events

  @spec new() :: map()
  def new do
    %{
      active_connections: nil,
      connections: %{},
      queue_pressure: :not_applicable,
      requests: %{}
    }
  end

  @spec sanitize([atom()], map(), map()) :: {:ok, map(), map()} | :unhandled
  def sanitize(@connection_stop, measurements, metadata) do
    {
      :ok,
      sanitize_connection_measurements(measurements),
      %{
        operation: normalize(metadata, :operation, @connection_operations, :unknown),
        outcome: normalize(metadata, :outcome, @connection_outcomes, :unknown)
      }
    }
  end

  def sanitize(@request_stop, measurements, metadata) do
    {
      :ok,
      sanitize_counted_duration(measurements),
      %{
        operation: normalize(metadata, :operation, @request_operations, :unknown),
        outcome: normalize(metadata, :outcome, @request_outcomes, :unknown)
      }
    }
  end

  def sanitize(_event, _measurements, _metadata), do: :unhandled

  @spec project([atom()], map(), map(), map()) :: {:ok, map()} | :unhandled
  def project(
        @connection_stop,
        %{active_connections: active_connections, count: 1, duration: duration},
        %{operation: operation, outcome: outcome},
        projection
      )
      when is_integer(active_connections) and active_connections >= 0 and is_integer(duration) and
             duration >= 0 do
    projection = %{
      projection
      | active_connections: active_connections,
        connections: update_duration(projection.connections, {operation, outcome}, duration)
    }

    {:ok, projection}
  end

  def project(
        @request_stop,
        %{count: 1, duration: duration},
        %{operation: operation, outcome: outcome},
        projection
      )
      when is_integer(duration) and duration >= 0 do
    {:ok,
     %{
       projection
       | requests: update_duration(projection.requests, {operation, outcome}, duration)
     }}
  end

  def project(event, _measurements, _metadata, _projection) when event in @events,
    do: :unhandled

  def project(_event, _measurements, _metadata, _projection), do: :unhandled

  defp sanitize_connection_measurements(%{
         active_connections: active_connections,
         count: 1,
         duration: duration
       })
       when is_integer(active_connections) and active_connections >= 0 and is_integer(duration) and
              duration >= 0 do
    %{active_connections: active_connections, count: 1, duration: duration}
  end

  defp sanitize_connection_measurements(_measurements), do: %{}

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
