defmodule Vxpipe.CallEngine.RemoteMCP.RestartSourceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog
  alias Vxpipe.CallEngine.RemoteMCPFixture
  alias Vxpipe.MCP.RuntimeAuthProvider

  test "host sources remain references and private snapshots require a host" do
    host = self()
    assert {:ok, ^host} = IntegrationCatalog.restart_source(host)
    assert {:ok, __MODULE__} = IntegrationCatalog.restart_source(__MODULE__)
    {private, _} = RemoteMCPFixture.binding!(nil, self(), "synthetic-private")
    assert {:error, :invalid_restart_source} = IntegrationCatalog.restart_source(private)
    assert {:error, :invalid_restart_source} = IntegrationCatalog.restart_source(nil)
  end

  test "inline catalogs accept only the existing saved credential descriptor shape" do
    endpoint = "https://mcp.example.test/mcp"

    {:ok, provider} =
      RuntimeAuthProvider.init(%{
        tenant: "tenant",
        connection_id: "connection",
        generation: 1,
        auth_method: "oauth",
        endpoint: endpoint,
        resolver: {Vxpipe.MCP.Test.RuntimeAuthFixture, :configured}
      })

    config = [endpoint: endpoint, authentication: :none, runtime_authentication: provider]
    {catalog, _} = RemoteMCPFixture.binding!(nil, self(), "unused", client_config: config)
    assert {:ok, ^catalog} = IntegrationCatalog.restart_source(catalog)

    for invalid <- [
          Keyword.put(config, :headers, [{"x-private", "synthetic-private"}]),
          Keyword.put(config, :authentication, :bearer),
          Keyword.put(config, :endpoint, "https://other.example.test/mcp"),
          Keyword.put(config, :runtime_authentication, %{provider | session: self()}),
          Keyword.put(config, :runtime_authentication, %{provider | generation: 0}),
          [{:endpoint, endpoint} | config]
        ] do
      {catalog, _} = RemoteMCPFixture.binding!(nil, self(), "unused", client_config: invalid)
      assert {:error, :invalid_restart_source} = IntegrationCatalog.restart_source(catalog)
    end
  end
end
