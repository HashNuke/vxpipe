defmodule Vxpipe.MCP.OwnedConnectionsTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, ReadyClientRuntime}

  @tag :capture_log
  test "rollback waits for transport descendants after integration registration disappears" do
    parent = owner(:draining_rollback)
    key = key()
    assert {:ok, connection} = open(parent, key)
    integration = Connection.owner(connection)

    transport =
      GenServer.whereis(
        {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:transport_workers, integration}}}
      )

    observer = self()

    spec =
      Supervisor.child_spec(
        {Task,
         fn ->
           Process.flag(:trap_exit, true)
           send(observer, {:draining_child, self()})
           receive do: (:release -> :ok)
         end}, restart: :temporary, shutdown: 1_000)

    assert {:ok, slow} = DynamicSupervisor.start_child(transport, spec)
    assert_receive {:draining_child, ^slow}
    transport_ref = Process.monitor(transport)
    integration_ref = Process.monitor(integration)
    Process.exit(integration, :kill)
    assert_receive {:DOWN, ^integration_ref, :process, ^integration, :killed}

    for {_, partition, _, _} <- Supervisor.which_children(Vxpipe.MCP.ConnectionRegistry),
        do: :sys.get_state(partition)

    assert Registry.lookup(Vxpipe.MCP.ConnectionRegistry, {:owner, parent, key}) == []

    start_supervised!(
      {Task, fn -> send(observer, {:rollback_done, Connections.close_owned([key], parent)}) end}
    )

    try do
      refute_receive {:rollback_done, :ok}, 100
    after
      send(slow, :release)
    end

    assert_receive {:rollback_done, :ok}, 1_000
    assert_receive {:DOWN, ^transport_ref, :process, ^transport, _reason}, 1_000
  end

  test "startup rollback closes selected keys in one exact owner without needing ready handles" do
    first_owner = owner(:rollback_first)
    second_owner = owner(:rollback_second)
    selected = [key(), key()]
    unrelated_key = key()

    connections =
      Enum.map(selected, fn key ->
        assert {:ok, connection} = open(first_owner, key)
        connection
      end)

    assert {:ok, independent} = open(second_owner, hd(selected))
    assert {:ok, unrelated} = open(first_owner, unrelated_key)

    clients =
      Map.new(connections, fn connection ->
        client = Connection.client(connection)
        {client, Process.monitor(client)}
      end)

    assert :ok = Connections.close_owned(selected, first_owner)

    for {client, monitor} <- clients do
      assert_receive {:DOWN, ^monitor, :process, ^client, _reason}
    end

    for connection <- [independent, unrelated] do
      assert {:ok, %{connection_status: :ready}} =
               ReadyClientRuntime.status(Connection.client(connection))
    end
  end

  test "equal credentials in two owners create separate descendants and lifetimes" do
    first_owner = owner(:first)
    second_owner = owner(:second)
    key = key()
    assert {:ok, first} = open(first_owner, key)
    assert {:ok, second} = open(second_owner, key)

    refute Connection.client(first) == Connection.client(second)
    refute Connection.owner(first) == Connection.owner(second)
    assert child?(first_owner, Connection.owner(first))
    assert child?(second_owner, Connection.owner(second))

    first_client = Connection.client(first)
    reference = Process.monitor(first_client)
    assert :ok = stop_supervised(:first)
    assert_receive {:DOWN, ^reference, :process, ^first_client, :shutdown}

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(second))
  end

  test "one owner reuses compatible normalized options" do
    owner = owner(:reuse)
    key = key()
    assert {:ok, first} = open(owner, key, limits: [max_response_bytes: 1_024])

    assert {:ok, ^first} =
             Connections.open(
               key,
               [limits: [max_response_bytes: 1_024], endpoint: "https://mcp.example.test/mcp"],
               owner: owner,
               runtime: ReadyClientRuntime
             )
  end

  for {label, config} <- [
        endpoint: [endpoint: "https://other.example.test/mcp"],
        response_limit: [limits: [max_response_bytes: 1_024]],
        static_credentials: [authentication: [type: :bearer, token: "synthetic-new-secret"]]
      ] do
    @config config
    test "one owner rejects incompatible #{label} without disturbing its session" do
      owner = owner(:policy)
      key = key()
      assert {:ok, first} = open(owner, key)
      assert {:error, :incompatible_connection} = open(owner, key, @config)

      assert {:ok, %{connection_status: :ready}} =
               ReadyClientRuntime.status(Connection.client(first))
    end
  end

  test "reuse compares effective policy after merging runtime options" do
    owner = owner(:effective_policy)
    key = key()
    assert {:ok, first} = open(owner, key)

    assert {:error, :incompatible_connection} =
             Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
               owner: owner,
               runtime: ReadyClientRuntime,
               runtime_options: [request_timeout: 1]
             )

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(first))
  end

  test "duplicate runtime options preserve the runtime's first-value policy" do
    owner = owner(:duplicate_policy)
    key = key()

    assert {:ok, first} =
             Connections.open(key, config(),
               owner: owner,
               runtime: ReadyClientRuntime,
               runtime_options: [request_timeout: 1, request_timeout: 30_000]
             )

    assert {:error, :incompatible_connection} = open(owner, key)

    assert {:ok, ^first} =
             Connections.open(key, config(),
               owner: owner,
               runtime: ReadyClientRuntime,
               runtime_options: [request_timeout: 1]
             )
  end

  test "an explicitly dead or missing owner never falls back to global reuse" do
    owner = owner(:dead)
    reference = Process.monitor(owner)
    key = key()
    assert {:ok, global} = Connections.open(key, config(), runtime: ReadyClientRuntime)
    assert :ok = stop_supervised(:dead)
    assert_receive {:DOWN, ^reference, :process, ^owner, :shutdown}

    assert {:error, :invalid_owner} = open(owner, key)
    missing = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:missing, make_ref()}}}
    assert {:error, :invalid_owner} = open(missing, key)
    assert {:ok, ^global} = Connections.lookup(key)
  end

  test "a delayed close targets its exact owner and session incarnation" do
    first_owner = owner(:close_first)
    second_owner = owner(:close_second)
    key = key()
    assert {:ok, first} = open(first_owner, key)
    assert {:ok, second} = open(second_owner, key)
    assert :ok = Connections.close(first)
    assert {:ok, replacement} = open(first_owner, key)
    refute Connection.owner(first) == Connection.owner(replacement)
    assert :ok = Connections.close(first)

    for connection <- [second, replacement] do
      assert {:ok, %{connection_status: :ready}} =
               ReadyClientRuntime.status(Connection.client(connection))
    end
  end

  test "local revocation closes every owner session for only the selected grant" do
    first_owner = owner(:revoke_first)
    second_owner = owner(:revoke_second)
    key = key()
    other_key = key()
    assert {:ok, first} = open(first_owner, key)
    assert {:ok, second} = open(second_owner, key)
    assert {:ok, global} = Connections.open(key, config(), runtime: ReadyClientRuntime)
    assert {:ok, unrelated} = open(second_owner, other_key)
    clients = Enum.map([first, second, global], &Connection.client/1)
    assert length(Enum.uniq(clients)) == 3
    monitors = Map.new(clients, &{&1, Process.monitor(&1)})

    assert :ok = Connections.revoke(key)

    for {client, reference} <- monitors do
      assert_receive {:DOWN, ^reference, :process, ^client, :shutdown}
    end

    assert {:error, :credential_revoked} = open(first_owner, key)

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(unrelated))
  end

  test "a failed initialization cannot retire another owner's session" do
    first_owner = owner(:ready)
    second_owner = owner(:failure)
    key = key()
    assert {:ok, first} = open(first_owner, key)

    assert {:error, {:unsupported_protocol_version, "unsupported"}} =
             Connections.open(key, config(),
               owner: second_owner,
               runtime: ReadyClientRuntime,
               runtime_options: [
                 test_status: %{connection_status: :ready, protocol_version: "unsupported"}
               ]
             )

    assert DynamicSupervisor.count_children(second_owner).active == 0

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(first))
  end

  test "scoped lookup and handle validation reject foreign and retired incarnations" do
    first_owner = owner(:handle_first)
    second_owner = owner(:handle_second)
    key = key()
    assert {:ok, first} = open(first_owner, key)
    assert {:ok, second} = open(second_owner, key)

    assert {:ok, ^first} = Connections.lookup(key, owner: first_owner)
    assert {:ok, ^second} = Connections.lookup(key, owner: second_owner)
    assert :error = Connections.lookup(key)
    assert Connections.owned_by?(first, first_owner)
    refute Connections.owned_by?(first, second_owner)

    foreign = Connection.new(key, Connection.owner(first), Connection.client(second))
    refute Connections.owned_by?(foreign, first_owner)

    assert :ok = Connections.close(first)
    assert {:ok, replacement} = open(first_owner, key)
    refute Connections.owned_by?(first, first_owner)
    assert Connections.owned_by?(replacement, first_owner)
  end

  test "concurrent reuse waits for the registered client to finish initialization" do
    owner = owner(:initializing)
    key = key()
    observer = self()

    {:ok, authentication} =
      Vxpipe.MCP.RuntimeAuthProvider.init(%{
        tenant: "owner-fixture",
        connection_id: key.integration_id,
        generation: 1,
        auth_method: "none",
        endpoint: "https://mcp.example.test/mcp",
        resolver:
          {Vxpipe.MCP.Test.RuntimeAuthFixture,
           {observer,
            fn ->
              send(observer, :reuse_authorized)
              {:ok, %{auth_method: "none", headers: []}}
            end}}
      })

    config = Keyword.put(config(), :runtime_authentication, authentication)

    opts = [
      owner: owner,
      runtime: ReadyClientRuntime,
      runtime_options: [test_initialization_observer: observer]
    ]

    start_supervised!(
      {Task, fn -> send(observer, {:first_open, Connections.open(key, config, opts)}) end},
      id: :first_open
    )

    assert_receive {:ready_client_initializing, client}

    try do
      start_supervised!(
        {Task, fn -> send(observer, {:second_open, Connections.open(key, config, opts)}) end},
        id: :second_open
      )

      assert_receive :reuse_authorized
      refute_receive {:second_open, _premature}, 100
      send(client, :finish_initialization)
      assert_receive {:first_open, {:ok, connection}}
      assert_receive {:second_open, {:ok, ^connection}}
    after
      send(client, :finish_initialization)
    end
  end

  test "lookup and provider-handle validation cannot publish an initializing client" do
    owner = owner(:unready_lookup)
    key = key()
    observer = self()

    start_supervised!(
      {Task,
       fn ->
         result =
           Connections.open(key, config(),
             owner: owner,
             runtime: ReadyClientRuntime,
             runtime_options: [test_initialization_observer: observer]
           )

         send(observer, {:opened, result})
       end},
      id: :opening
    )

    assert_receive {:ready_client_initializing, client}

    try do
      {:ok, integration} = Vxpipe.MCP.ConnectionNames.lookup(:owner, key, owner)
      candidate = Connection.new(key, integration, client, owner)

      start_supervised!(
        {Task,
         fn ->
           send(observer, :lookup_started)
           send(observer, {:looked_up, Connections.lookup(key, owner: owner)})
         end},
        id: :lookup
      )

      start_supervised!(
        {Task,
         fn ->
           send(observer, :validation_started)
           send(observer, {:validated, Connections.owned_by?(candidate, owner)})
         end},
        id: :validation
      )

      assert_receive :lookup_started
      assert_receive :validation_started
      refute_receive {:looked_up, {:ok, _premature}}, 100
      refute_receive {:validated, true}, 100
      send(client, :finish_initialization)
      assert_receive {:opened, {:ok, ^candidate}}
      assert_receive {:looked_up, {:ok, ^candidate}}
      assert_receive {:validated, true}
    after
      send(client, :finish_initialization)
    end
  end

  test "lookup rejects registry entries from different integration incarnations" do
    owner = owner(:mixed_registry)
    key = key()
    assert {:ok, first} = open(owner, key)
    integration = Connection.owner(first)
    client = Connection.client(first)
    client_ref = Process.monitor(client)
    integration_ref = Process.monitor(integration)
    :ok = :sys.suspend(integration)

    try do
      Process.exit(client, :kill)
      assert_receive {:DOWN, ^client_ref, :process, ^client, :killed}

      name =
        Vxpipe.MCP.ConnectionNames.via(:client, key, owner, %{integration_owner: self()})

      replacement_client = start_supervised!({Vxpipe.MCP.ReadyClient, name: name})
      mixed = Connection.new(key, integration, replacement_client, owner)
      assert :error = Connections.lookup(key, owner: owner)
      refute Connections.owned_by?(mixed, owner)
    after
      :sys.resume(integration)
    end

    assert_receive {:DOWN, ^integration_ref, :process, ^integration, :shutdown}
  end

  defp owner(id) do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:test_session_owner, make_ref()}}}
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name}, id: id)
  end

  defp open(owner, key, overrides \\ []) do
    Connections.open(key, Keyword.merge(config(), overrides),
      owner: owner,
      runtime: ReadyClientRuntime
    )
  end

  defp config, do: [endpoint: "https://mcp.example.test/mcp"]

  defp child?(supervisor, child) do
    Enum.any?(DynamicSupervisor.which_children(supervisor), fn {_id, pid, _type, _modules} ->
      pid == child
    end)
  end

  defp key do
    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "owned-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    on_exit(fn -> Connections.close(key) end)
    key
  end
end
