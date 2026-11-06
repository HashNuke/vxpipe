defmodule Vxpipe.Console.Test.SavedMCPWireConnectionProvider do
  @moduledoc false

  def open(key, config) do
    %URI{scheme: "https", host: "mcp.example.test", port: port, path: "/mcp"} =
      URI.parse(Keyword.fetch!(config, :endpoint))

    config = Keyword.put(config, :endpoint, "http://127.0.0.1:#{port}/mcp")
    Vxpipe.MCP.Connections.open_loopback_test(key, config)
  end
end
