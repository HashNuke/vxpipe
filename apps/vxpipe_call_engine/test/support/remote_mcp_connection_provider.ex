defmodule Vxpipe.CallEngine.TestRemoteMCPConnectionProvider do
  @moduledoc false

  alias Vxpipe.CallEngine.TestRemoteMCPClient
  alias Vxpipe.MCP.{Connection, Connections}

  def open(key, config) do
    announce(config, key)
    {:ok, Connection.new(key, self(), Keyword.fetch!(config, :test_client))}
  end

  def open(key, config, options) do
    announce(config, key)

    options =
      Keyword.merge(options,
        runtime: TestRemoteMCPClient,
        runtime_options: [test_client: Keyword.fetch!(config, :test_client)]
      )

    client_config = [
      endpoint: "https://fixture.example.test/mcp",
      limits: Keyword.get(config, :limits, [])
    ]

    Connections.open(key, client_config, options)
  end

  defp announce(config, key) do
    observer = Keyword.fetch!(config, :test_observer)
    send(observer, {:test_remote_mcp_opened, key, config})

    if Keyword.get(config, :test_gate_initialization, false) do
      send(observer, {:test_remote_mcp_initializing, self()})

      receive do
        :test_remote_mcp_initialized -> :ok
      end
    end
  end
end
