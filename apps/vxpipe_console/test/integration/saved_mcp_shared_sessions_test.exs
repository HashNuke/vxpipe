defmodule Vxpipe.Console.Integration.SavedMCPSharedSessionsTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls.MCPTransportCredentials
  alias Vxpipe.Console.Test.SavedMCPWireConnectionProvider
  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, RuntimeAuthProvider}
  alias Vxpipe.Persistence.MCP.ConnectionStore

  for change <- [:disconnect, :replacement, :local_revocation] do
    @tag change: change
    test "two live saved sessions observe #{change} without sharing lifetime", c do
      {:ok, key} =
        ConnectionKey.new(
          scope: :tenant,
          tenant_id: c.tenant,
          integration_id: c.connection.id,
          credential_generation: "1"
        )

      {:ok, auth} =
        RuntimeAuthProvider.init(%{
          tenant: c.tenant,
          connection_id: c.connection.id,
          generation: 1,
          auth_method: "bearer",
          endpoint: c.connection.endpoint,
          resolver: {MCPTransportCredentials, :configured}
        })

      config = [endpoint: c.connection.endpoint, runtime_authentication: auth, use_sse: false]
      hosts = for _ <- 1..2, do: Vxpipe.MCP.Test.SessionHost.start!()

      connections =
        for host <- hosts do
          assert {:ok, connection} = SavedMCPWireConnectionProvider.open(key, config, owner: host)

          assert {:ok, _} =
                   ExMCP.Client.call_tool(
                     Connection.client(connection),
                     "lookup_customer",
                     %{"customer_id" => "customer-42"},
                     timeout: 1_000
                   )

          connection
        end

      assert_receive {:remote_mcp_wire_initialized, first}
      assert_receive {:remote_mcp_wire_initialized, second}
      refute first == second
      for _ <- connections, do: assert_receive({:remote_mcp_wire_request, "tools/call", _, _})
      clients = Enum.map(connections, &Connection.client/1)
      monitors = Enum.map(clients, &{&1, Process.monitor(&1)})

      case c.change do
        :disconnect ->
          assert {:ok, _} = ConnectionStore.revoke(c.context, c.tenant, c.connection.id, 1)

        :replacement ->
          assert {:ok, _} =
                   ConnectionStore.replace(
                     c.context,
                     c.tenant,
                     c.connection.id,
                     1,
                     c.attributes,
                     %{"token" => "replacement"}
                   )

        :local_revocation ->
          assert :ok = Connections.revoke(key)
      end

      if c.change != :local_revocation do
        for connection <- connections do
          assert {:error, _} =
                   ExMCP.Client.call_tool(
                     Connection.client(connection),
                     "lookup_customer",
                     %{"customer_id" => "customer-43"},
                     timeout: 1_000
                   )

          assert :ok = Connections.close(connection)
        end

        refute_received {:remote_mcp_wire_delete, _}
      else
        assert {:ok, %{status: "connected", generation: 1}} =
                 ConnectionStore.get(c.context, c.tenant, c.connection.id)

        for host <- hosts,
            do:
              assert({:error, _} = SavedMCPWireConnectionProvider.open(key, config, owner: host))
      end

      for {client, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^client, _}, 1_000)

      refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    end
  end
end
