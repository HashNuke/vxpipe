defmodule Vxpipe.Console.Test.DiagnosticsIngressLatency do
  @moduledoc "Complete same-VM ingress invocation to synthetic provider receipt evidence."
  alias Vxpipe.Console.Test.DiagnosticsSchedule

  def summarize(samples, rooms, humans, mode) do
    inputs = rooms * humans
    plan = DiagnosticsSchedule.profile(mode)

    if Enum.sort(Map.keys(samples)) != Enum.to_list(0..(inputs - 1)),
      do: raise(ArgumentError, "missing input latency samples")

    durations =
      Enum.flat_map(0..(inputs - 1), fn index ->
        rows = Map.fetch!(samples, index)
        expected = DiagnosticsSchedule.frame_count(index, rooms, humans, mode)

        if length(rows) != expected,
          do: raise(ArgumentError, "missing frame latency samples")

        rows
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [previous, current] ->
          if current.ingress_us < previous.ingress_us or
               current.provider_us < previous.provider_us,
             do: raise(ArgumentError, "backwards frame latency clock")
        end)

        rows
        |> Enum.with_index()
        |> Enum.flat_map(fn {row, sequence} ->
          unless row.sequence == sequence and is_integer(row.ingress_us) and
                   is_integer(row.provider_us) and row.provider_us >= row.ingress_us,
                 do: raise(ArgumentError, "invalid frame latency sample")

          offset = sequence * 32_000_000 + div(32_000_000 * index, inputs)

          if offset >= plan.measurement_start_ns and offset < plan.duration_ns,
            do: [row.provider_us - row.ingress_us],
            else: []
        end)
      end)

    count = length(durations)
    %{count: count, p95_us: durations |> Enum.sort() |> Enum.at(div(95 * count + 99, 100) - 1)}
  end
end
