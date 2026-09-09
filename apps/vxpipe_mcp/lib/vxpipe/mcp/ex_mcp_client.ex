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
end
