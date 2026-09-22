defmodule Vxpipe.CallEngine.Speech.ToolArguments do
  @moduledoc false
  @maximum_bytes 65_536
  @maximum_depth 16

  def valid?(value) when is_map(value) and not is_struct(value) do
    # Bound traversal with a lower size estimate before measuring JSON escapes.
    with {:ok, _remaining} <- measure(value, @maximum_bytes, 0) do
      byte_size(JSON.encode!(value)) <= @maximum_bytes
    else
      _invalid -> false
    end
  end

  def valid?(_value), do: false

  defp measure(_value, budget, depth) when budget < 0 or depth > @maximum_depth, do: :error

  defp measure(value, budget, _depth) when is_binary(value) do
    if byte_size(value) <= budget and String.valid?(value),
      do: {:ok, budget - byte_size(value) - 2},
      else: :error
  end

  defp measure(value, budget, _depth) when is_number(value) or value in [nil, true, false],
    do: {:ok, budget - 1}

  defp measure(value, budget, depth) when is_list(value),
    do: sequence(value, budget, depth)

  defp measure(value, budget, depth) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, budget - 2}, fn
      {key, nested}, {:ok, remaining} when is_binary(key) ->
        with {:ok, remaining} <- measure(key, remaining, depth + 1),
             {:ok, remaining} <- measure(nested, remaining - 1, depth + 1) do
          {:cont, {:ok, remaining}}
        else
          _invalid -> {:halt, :error}
        end

      _entry, _budget ->
        {:halt, :error}
    end)
  end

  defp measure(_value, _budget, _depth), do: :error

  defp sequence(values, budget, depth), do: elements(values, budget - 2, depth)

  defp elements([], budget, _depth) when budget >= 0, do: {:ok, budget}

  defp elements([value | rest], budget, depth) do
    with {:ok, remaining} <- measure(value, budget, depth + 1),
         do: elements(rest, remaining, depth)
  end

  defp elements(_values, _budget, _depth), do: :error
end
