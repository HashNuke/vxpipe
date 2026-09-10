defmodule Vxpipe.CallEngine.RemoteMCP.Executor do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.RuntimeBinding
  alias Vxpipe.MCP.{Connection, Invocation}

  @spec execute(RuntimeBinding.t(), map()) ::
          {:ok, map()}
          | {:error,
             :invalid_arguments | :invalid_result | :tool_failed | :unknown | :unknown_tool}
  def execute(%RuntimeBinding{} = binding, arguments) when is_map(arguments) do
    Invocation.call(
      Connection.client(binding.connection),
      binding.catalog,
      binding.resolved.remote_name,
      arguments,
      protocol: binding.protocol,
      deadline_ms: binding.resolved.invocation_deadline_ms,
      max_result_bytes: binding.resolved.maximum_result_bytes
    )
    |> normalize_result()
  end

  defp normalize_result({:ok, result}) when is_map(result), do: {:ok, result}
  defp normalize_result({:error, :invalid_arguments}), do: {:error, :invalid_arguments}

  defp normalize_result({:error, reason})
       when reason in [:invalid_tool_result, :result_too_large],
       do: {:error, :invalid_result}

  defp normalize_result({:error, reason})
       when reason in [:invocation_timed_out, :outcome_unknown],
       do: {:error, :unknown}

  defp normalize_result({:error, :unknown_tool}), do: {:error, :unknown_tool}
  defp normalize_result(_failure), do: {:error, :tool_failed}
end
