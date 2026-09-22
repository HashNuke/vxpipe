defmodule Vxpipe.CallEngine.CallLoad.Metrics do
  @moduledoc false

  def validate(calls, turns, timeout)
      when calls in 2..10 and turns in 1..4 and timeout in 1_000..120_000,
      do: :ok

  def validate(_, _, _), do: {:error, :bounds}

  def percentiles([]), do: %{count: 0, p50: nil, p95: nil, p99: nil}

  def percentiles(values) do
    sorted = Enum.sort(values)
    count = length(sorted)

    Map.new([p50: 50, p95: 95, p99: 99], fn {key, percentile} ->
      {key, Enum.at(sorted, ceil(count * percentile / 100) - 1)}
    end)
    |> Map.put(:count, count)
  end
end
