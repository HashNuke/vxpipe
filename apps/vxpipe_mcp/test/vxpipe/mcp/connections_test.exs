defmodule Vxpipe.MCP.ConnectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ReadyClientRuntime}

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
        headers: [{"authorization", authorization}]
      ],
      runtime: ReadyClientRuntime
    )
  end

  defp key(generation) do
    suffix = System.unique_integer([:positive, :monotonic])

    {:ok, key} =
      ConnectionKey.new(
        integration_id: "orders-#{suffix}",
        credential_generation: generation
      )

    key
  end

  defp close_on_exit(keys) do
    on_exit(fn -> Enum.each(keys, &Connections.close/1) end)
  end
end
