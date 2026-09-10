defmodule Vxpipe.CallEngine.Tool.InvocationExecution do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{Context, InvocationBinding}

  @spec run(InvocationBinding.t(), map(), Context.t(), pos_integer()) ::
          {:ok, term()} | {:error, :invalid_result | :tool_failed}
  def run(
        %InvocationBinding{handler: {:host, action}},
        arguments,
        %Context{} = context,
        maximum_result_bytes
      )
      when is_map(arguments) and is_integer(maximum_result_bytes) and maximum_result_bytes > 0 do
    action
    |> execute(arguments, context)
    |> normalize(maximum_result_bytes)
  end

  def run(_binding, _arguments, _context, _maximum_result_bytes), do: {:error, :tool_failed}

  defp execute(action, arguments, context) do
    try do
      action.execute(arguments, context)
    rescue
      _exception -> {:error, :tool_failed}
    catch
      _kind, _reason -> {:error, :tool_failed}
    end
  end

  defp normalize({:ok, result}, maximum_result_bytes) do
    try do
      if byte_size(JSON.encode!(result)) <= maximum_result_bytes do
        {:ok, result}
      else
        {:error, :invalid_result}
      end
    rescue
      _exception -> {:error, :invalid_result}
    end
  end

  defp normalize({:error, _reason}, _maximum_result_bytes), do: {:error, :tool_failed}
  defp normalize(_result, _maximum_result_bytes), do: {:error, :invalid_result}
end
