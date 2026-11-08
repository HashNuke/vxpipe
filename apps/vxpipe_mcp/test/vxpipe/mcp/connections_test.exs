defmodule Vxpipe.MCP.ConnectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ReadyClientRuntime}

  setup do
    %{host: Vxpipe.MCP.Test.SessionHost.start!()}
  end

  test "reused sessions require current runtime credentials without retiring unrelated access", %{
    host: host
  } do
    key = tenant_key("tenant", "reused-#{System.unique_integer([:positive])}")

    valid =
      {:ok, %{auth_method: "bearer", headers: [{"authorization", "Bearer synthetic-token"}]}}

    credentials = start_supervised!({Agent, fn -> valid end})

    {:ok, authentication} =
      Vxpipe.MCP.RuntimeAuthProvider.init(%{
        tenant: "tenant",
        connection_id: key.integration_id,
        generation: 1,
        auth_method: "bearer",
        endpoint: "https://mcp.example.test/mcp",
        resolver:
          {Vxpipe.MCP.Test.RuntimeAuthFixture, {self(), fn -> Agent.get(credentials, & &1) end}}
      })

    config = [endpoint: authentication.endpoint, runtime_authentication: authentication]
    assert {:ok, first} = Connections.open(key, config, owner: host, runtime: ReadyClientRuntime)
    Agent.update(credentials, fn _ -> {:error, :revoked} end)

    assert {:error, :connection_failed} =
             Connections.open(key, config, owner: host, runtime: ReadyClientRuntime)

    assert {:ok, ^first} = Connections.lookup(key, owner: host)

    Agent.update(credentials, fn _ -> valid end)
    assert {:ok, ^first} = Connections.open(key, config, owner: host, runtime: ReadyClientRuntime)
  end

  test "reuses one ready session per integration and credential generation", %{host: host} do
    key = key("generation-a")
    next_key = key("generation-b")

    assert {:ok, first} = open(host, key, "Bearer first-secret")
    assert {:ok, reused} = open(host, key, "Bearer first-secret")
    assert {:ok, next_generation} = open(host, next_key, "Bearer next-secret")

    assert Connection.owner(first) == Connection.owner(reused)
    assert Connection.client(first) == Connection.client(reused)
    refute Connection.owner(first) == Connection.owner(next_generation)
    refute Connection.client(first) == Connection.client(next_generation)

    refute inspect(first) =~ "first-secret"
    refute inspect(first) =~ "authorization"
  end

  test "never shares a connection between tenant scopes", %{host: host} do
    suffix = System.unique_integer([:positive, :monotonic])
    integration_id = "records-#{suffix}"

    tenant_a = tenant_key("tenant-a", integration_id)
    tenant_b = tenant_key("tenant-b", integration_id)

    assert {:ok, first} = open(host, tenant_a, "Bearer tenant-a-private")
    assert {:ok, second} = open(host, tenant_b, "Bearer tenant-b-private")

    refute Connection.owner(first) == Connection.owner(second)
    refute Connection.client(first) == Connection.client(second)
  end

  test "requires one explicit well-formed connection scope" do
    base = [integration_id: "records", credential_generation: "generation-one"]

    assert {:error, :invalid_connection_key} = ConnectionKey.new(base)

    assert {:error, :invalid_connection_key} =
             ConnectionKey.new([scope: :tenant] ++ base)

    assert {:error, :invalid_connection_key} =
             ConnectionKey.new([scope: :application, tenant_id: "tenant-a"] ++ base)
  end

  test "retires the complete scoped connection subtree", %{host: host} do
    key = key("retired")
    assert {:ok, connection} = open(host, key, "Bearer private")

    owner_ref = Process.monitor(Connection.owner(connection))
    client_ref = Process.monitor(Connection.client(connection))

    assert :ok = Connections.close(connection)
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}
    assert_receive {:DOWN, ^client_ref, :process, _pid, :shutdown}
    assert :error = Connections.lookup(key, owner: host)
  end

  test "closing an old handle cannot retire a replacement with the same credential key", %{
    host: host
  } do
    key = key("reopened")
    assert {:ok, first} = open(host, key, "Bearer private")
    assert :ok = Connections.close(first)
    assert {:ok, replacement} = open(host, key, "Bearer private")

    refute Connection.owner(first) == Connection.owner(replacement)
    refute Connection.client(first) == Connection.client(replacement)
    assert :ok = Connections.close(first)

    assert {:ok, ^replacement} = Connections.lookup(key, owner: host)

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(replacement))
  end

  test "local revocation retires an integration before its client is registered", %{host: host} do
    observer = self()
    key = key("pending-close")

    start_supervised!(
      {Task,
       fn ->
         result =
           Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
             owner: host,
             runtime: ReadyClientRuntime,
             runtime_options: [test_spec_observer: observer]
           )

         send(observer, {:pending_open_result, result})
       end}
    )

    assert_receive {:pending_integration, integration}
    reference = Process.monitor(integration)

    try do
      assert :ok = Connections.revoke(key)
      assert_receive {:DOWN, ^reference, :process, ^integration, _}, 300
      assert_receive {:pending_open_result, {:error, :connection_failed}}
      assert :error = Connections.lookup(key, owner: host)
    after
      send(integration, :release_spec)
    end
  end

  test "client loss retires its session identity before a replacement can be opened", %{
    host: host
  } do
    key = key("client-lost")
    assert {:ok, first} = open(host, key, "Bearer private")
    owner_ref = Process.monitor(Connection.owner(first))
    client_ref = Process.monitor(Connection.client(first))

    Process.exit(Connection.client(first), :kill)

    assert_receive {:DOWN, ^client_ref, :process, _pid, :killed}
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}, 1_000
    assert :error = Connections.lookup(key, owner: host)

    assert {:ok, replacement} = open(host, key, "Bearer private")
    refute Connection.owner(first) == Connection.owner(replacement)
    assert :ok = Connections.close(first)
    assert {:ok, ^replacement} = Connections.lookup(key, owner: host)

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(replacement))
  end

  test "revokes one credential generation and refuses to reopen it", %{host: host} do
    key = key("revoked")
    assert {:ok, connection} = open(host, key, "Bearer private")

    owner_ref = Process.monitor(Connection.owner(connection))
    client_ref = Process.monitor(Connection.client(connection))

    assert :ok = Connections.revoke(key)
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}
    assert_receive {:DOWN, ^client_ref, :process, _pid, :shutdown}
    assert :error = Connections.lookup(key, owner: host)

    assert {:error, :credential_revoked} = open(host, key, "Bearer private")
    assert :error = Connections.lookup(key, owner: host)
  end

  test "rejects and cleans up a session that negotiates another protocol version", %{host: host} do
    key = key("wrong-version")

    assert {:error, {:unsupported_protocol_version, "2026-07-28"}} =
             Connections.open(
               key,
               [endpoint: "https://mcp.example.test/rpc"],
               owner: host,
               runtime: ReadyClientRuntime,
               runtime_options: [
                 test_status: %{
                   connection_status: :ready,
                   protocol_version: "2026-07-28"
                 }
               ]
             )

    assert :error = Connections.lookup(key, owner: host)
  end

  test "opens plaintext only through the explicit loopback test entry", %{host: host} do
    key = key("loopback")

    assert {:error, :https_required} =
             Connections.open(
               key,
               [endpoint: "http://127.0.0.1:4321/mcp"],
               owner: host,
               runtime: ReadyClientRuntime
             )

    assert {:ok, connection} =
             Connections.open_loopback_test(
               key,
               [endpoint: "http://127.0.0.1:4321/mcp"],
               owner: host,
               runtime: ReadyClientRuntime
             )

    assert Connection.key(connection) == key
  end

  defp open(host, key, authorization) do
    Connections.open(
      key,
      [
        endpoint: "https://mcp.example.test/rpc",
        authentication: [
          type: :custom_headers,
          headers: [{"authorization", authorization}]
        ]
      ],
      owner: host,
      runtime: ReadyClientRuntime
    )
  end

  defp key(generation) do
    suffix = System.unique_integer([:positive, :monotonic])

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "orders-#{suffix}",
        credential_generation: generation
      )

    key
  end

  defp tenant_key(tenant_id, integration_id) do
    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: tenant_id,
        integration_id: integration_id,
        credential_generation: "generation-one"
      )

    key
  end
end
