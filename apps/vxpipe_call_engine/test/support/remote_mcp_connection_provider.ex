defmodule Vxpipe.CallEngine.TestRemoteMCPConnectionProvider do
  @moduledoc false

  alias Vxpipe.CallEngine.TestRemoteMCPClient
  alias Vxpipe.MCP.{Connection, Connections}

  def open(key, config) do
    announce(config, key)
    {:ok, Connection.new(key, self(), Keyword.fetch!(config, :test_client))}
  end

  def open(key, config, options) do
    send(Keyword.fetch!(config, :test_observer), {:test_remote_mcp_open_options, key, options})
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

    if Keyword.get(config, :test_fail_open, false) do
      children = DynamicSupervisor.which_children(Keyword.fetch!(options, :owner))
      send(Keyword.fetch!(config, :test_observer), {:test_mcp_partial_children, children})
      {:error, :fixture_failure}
    else
      Connections.open(key, client_config, options)
    end
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
