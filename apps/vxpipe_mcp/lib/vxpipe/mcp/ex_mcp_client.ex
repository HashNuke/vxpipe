defmodule Vxpipe.MCP.ExMCPClient do
  @moduledoc false

  @behaviour Vxpipe.MCP.ProtocolClient

  @impl true
  def list_tools(client, cursor, timeout) do
    params = if cursor, do: %{"cursor" => cursor}, else: %{}

    ExMCP.Client.make_request(
      client,
      "tools/list",
      params,
      [
        format: :map,
        timeout: timeout,
        retry_policy: false,
        http_stream_retry: :safe_only,
        max_mrtr_rounds: 0
      ],
      timeout
    )
  end

  @impl true
  def call_tool(client, name, arguments, timeout) do
    params = %{
      "name" => name,
      "arguments" => arguments,
      "_meta" => %{"progressToken" => System.unique_integer([:positive, :monotonic])}
    }

    client
    |> ExMCP.Client.make_request(
      "tools/call",
      params,
      [
        format: :map,
        timeout: timeout,
        retry_policy: false,
        http_stream_retry: :safe_only,
        max_mrtr_rounds: 0
      ],
      timeout
    )
    |> normalize_invocation_result()
  end

  defp normalize_invocation_result({:ok, result}) when is_map(result), do: {:ok, result}

  defp normalize_invocation_result({:error, reason})
       when reason in [:not_connected, :request_too_large],
       do: {:error, :not_submitted}

  defp normalize_invocation_result({:error, %ExMCP.Error.ProtocolError{}}),
    do: {:error, :remote_error}

  defp normalize_invocation_result({:error, %{"code" => code}}) when is_integer(code),
    do: {:error, :remote_error}

  defp normalize_invocation_result({:error, %{type: :protocol_error}}),
    do: {:error, :remote_error}

  defp normalize_invocation_result({:error, _reason}), do: {:error, :outcome_unknown}
  defp normalize_invocation_result(_other), do: {:error, :outcome_unknown}
end
