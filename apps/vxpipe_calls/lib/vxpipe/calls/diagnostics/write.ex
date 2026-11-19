defmodule Vxpipe.Calls.Diagnostics.Write do
  @moduledoc false
  alias Vxpipe.Calls.{LatencyRun, TurnDiagnostic}
  @enforce_keys [:function, :arguments]
  @derive {Inspect, only: [:function]}
  defstruct @enforce_keys

  def new({:run, %LatencyRun{} = run}) do
    with {:ok, run} <- LatencyRun.new(Map.from_struct(run)) do
      {:ok, %__MODULE__{function: :put_run, arguments: compact([run])}}
    else
      _invalid -> {:error, :invalid_write}
    end
  end

  def new({:turn, tenant, call, incarnation, %TurnDiagnostic{} = turn}) do
    attrs = turn |> Map.from_struct() |> Map.drop([:durations_us, :metric_reasons, :quality])

    with true <- Enum.all?([tenant, call, incarnation], &identifier?/1),
         {:ok, turn} <- TurnDiagnostic.new(attrs) do
      {:ok,
       %__MODULE__{function: :put_turn, arguments: compact([tenant, call, incarnation, turn])}}
    else
      _invalid -> {:error, :invalid_write}
    end
  end

  def new(_operation), do: {:error, :invalid_write}

  def run(%__MODULE__{} = write, {module, context}),
    do: apply(module, write.function, [context | write.arguments])

  def success?(%__MODULE__{} = write, {:ok, record}), do: record == List.last(write.arguments)
  def success?(%__MODULE__{}, _result), do: false

  defp compact(value) when is_binary(value), do: :binary.copy(value)
  defp compact(value) when is_list(value), do: Enum.map(value, &compact/1)

  defp compact(value) when is_map(value),
    do: Map.new(Map.to_list(value), fn {key, entry} -> {key, compact(entry)} end)

  defp compact(value), do: value

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)
end
