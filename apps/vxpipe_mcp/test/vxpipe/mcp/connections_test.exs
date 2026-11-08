defmodule Vxpipe.MCP.ConnectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ReadyClientRuntime}

  test "reused sessions require current runtime credentials without retiring unrelated access" do
    key = tenant_key("tenant", "reused-#{System.unique_integer([:positive])}")
    close_on_exit([key])

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
    assert {:ok, first} = Connections.open(key, config, runtime: ReadyClientRuntime)
    Agent.update(credentials, fn _ -> {:error, :revoked} end)

    assert {:error, :connection_failed} =
             Connections.open(key, config, runtime: ReadyClientRuntime)

    assert {:ok, ^first} = Connections.lookup(key)

    Agent.update(credentials, fn _ -> valid end)
    assert {:ok, ^first} = Connections.open(key, config, runtime: ReadyClientRuntime)
  end

  test "reuses one ready session per integration and credential generation" do
    key = key("generation-a")
    next_key = key("generation-b")
    close_on_exit([key, next_key])

    assert {:ok, first} = open(key, "Bearer first-secret")
    assert {:ok, reused} = open(key, "Bearer changed-but-same-generation")
    assert {:ok, next_generation} = open(next_key, "Bearer next-secret")

    assert Connection.owner(first) == Connection.owner(reused)
    assert Connection.client(first) == Connection.client(reused)
    refute Connection.owner(first) == Connection.owner(next_generation)
    refute Connection.client(first) == Connection.client(next_generation)

    refute inspect(first) =~ "first-secret"
    refute inspect(first) =~ "authorization"
  end

  test "never shares a connection between tenant scopes" do
    suffix = System.unique_integer([:positive, :monotonic])
    integration_id = "records-#{suffix}"

    tenant_a = tenant_key("tenant-a", integration_id)
    tenant_b = tenant_key("tenant-b", integration_id)
    close_on_exit([tenant_a, tenant_b])

    assert {:ok, first} = open(tenant_a, "Bearer tenant-a-private")
    assert {:ok, second} = open(tenant_b, "Bearer tenant-b-private")

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

  test "retires the complete scoped connection subtree" do
    key = key("retired")
    close_on_exit([key])
    assert {:ok, connection} = open(key, "Bearer private")

    owner_ref = Process.monitor(Connection.owner(connection))
    client_ref = Process.monitor(Connection.client(connection))

    assert :ok = Connections.close(connection)
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}
    assert_receive {:DOWN, ^client_ref, :process, _pid, :shutdown}
    assert :error = Connections.lookup(key)
  end

  test "closing an old handle cannot retire a replacement with the same credential key" do
    key = key("reopened")
    close_on_exit([key])
    assert {:ok, first} = open(key, "Bearer private")
    assert :ok = Connections.close(first)
    assert {:ok, replacement} = open(key, "Bearer private")

    refute Connection.owner(first) == Connection.owner(replacement)
    refute Connection.client(first) == Connection.client(replacement)
    assert :ok = Connections.close(first)

    assert {:ok, ^replacement} = Connections.lookup(key)

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(replacement))
  end

  test "client loss retires its session identity before a replacement can be opened" do
    key = key("client-lost")
    close_on_exit([key])
    assert {:ok, first} = open(key, "Bearer private")
    owner_ref = Process.monitor(Connection.owner(first))
    client_ref = Process.monitor(Connection.client(first))

    Process.exit(Connection.client(first), :kill)

    assert_receive {:DOWN, ^client_ref, :process, _pid, :killed}
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}, 1_000
    assert :error = Connections.lookup(key)

    assert {:ok, replacement} = open(key, "Bearer private")
    refute Connection.owner(first) == Connection.owner(replacement)
    assert :ok = Connections.close(first)
    assert {:ok, ^replacement} = Connections.lookup(key)

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(replacement))
  end

  test "revokes one credential generation and refuses to reopen it" do
    key = key("revoked")
    assert {:ok, connection} = open(key, "Bearer private")

    owner_ref = Process.monitor(Connection.owner(connection))
    client_ref = Process.monitor(Connection.client(connection))

    assert :ok = Connections.revoke(key)
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :shutdown}
    assert_receive {:DOWN, ^client_ref, :process, _pid, :shutdown}
    assert :error = Connections.lookup(key)

    assert {:error, :credential_revoked} = open(key, "Bearer private")
    assert :error = Connections.lookup(key)
  end

  test "rejects and cleans up a session that negotiates another protocol version" do
    key = key("wrong-version")
    close_on_exit([key])

    assert {:error, {:unsupported_protocol_version, "2026-07-28"}} =
             Connections.open(
               key,
               [endpoint: "https://mcp.example.test/rpc"],
               runtime: ReadyClientRuntime,
               runtime_options: [
                 test_status: %{
                   connection_status: :ready,
                   protocol_version: "2026-07-28"
                 }
               ]
             )

    assert :error = Connections.lookup(key)
  end

  test "opens plaintext only through the explicit loopback test entry" do
    key = key("loopback")
    close_on_exit([key])

    assert {:error, :https_required} =
             Connections.open(
               key,
               [endpoint: "http://127.0.0.1:4321/mcp"],
               runtime: ReadyClientRuntime
             )

    assert {:ok, connection} =
             Connections.open_loopback_test(
               key,
               [endpoint: "http://127.0.0.1:4321/mcp"],
               runtime: ReadyClientRuntime
             )

    assert Connection.key(connection) == key
  end

  defp open(key, authorization) do
    Connections.open(
      key,
      [
        endpoint: "https://mcp.example.test/rpc",
        authentication: [
          type: :custom_headers,
          headers: [{"authorization", authorization}]
        ]
      ],
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

  defp close_on_exit(keys) do
    on_exit(fn -> Enum.each(keys, &Connections.close/1) end)
  end
end
