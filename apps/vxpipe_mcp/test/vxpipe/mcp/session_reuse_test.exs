defmodule Vxpipe.MCP.SessionReuseTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    Connection,
    ConnectionKey,
    Connections,
    ReadyClientRuntime,
    RuntimeAuthProvider
  }

  alias Vxpipe.MCP.SessionLifecycle

  @moduletag :capture_log

  for cancellation <- [:deadline, :caller_death, :host_stop, :host_death, :session_close] do
    @cancellation cancellation

    test "#{cancellation} cancels reused authorization before reporting completion" do
      observer = self()
      host = host(:host)
      other_host = host(:other_host)
      key = key()
      config = config(observer, :blocked)
      assert {:ok, first} = open(host, key, config)
      assert {:ok, other} = open(other_host, key, config)
      timeout = if @cancellation == :deadline, do: 250, else: 5_000

      caller =
        start_supervised!(
          {Task,
           fn ->
             result = open(host, key, config, deadline: now() + timeout)
             send(observer, {:reuse_result, result})
           end},
          id: :reuse
        )

      assert_receive {:authorization_started, worker}, 1_000
      worker_ref = Process.monitor(worker)

      try do
        case @cancellation do
          :deadline -> :ok
          :caller_death -> Process.exit(caller, :kill)
          :host_stop -> stop_supervised(:host)
          :host_death -> Process.exit(host, :kill)
          :session_close -> assert :ok = Connections.close(first)
        end

        if @cancellation != :caller_death do
          assert_receive {:reuse_result, {:error, :connection_failed}}, 750
          # A completed open failure must not leave credential callbacks running.
          assert Process.info(worker) == nil
        end

        refute worker == caller
        assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 750

        if preserves_session?(@cancellation) do
          assert {:ok, ^first} = Connections.lookup(key, owner: host)
        end

        assert {:ok, ^other} = Connections.lookup(key, owner: other_host)
        send(worker, :release_authorization)
        refute_receive :authorization_completed, 20
      after
        Process.exit(caller, :kill)
        send(worker, :release_authorization)
      end
    end
  end

  test "one opener's timeout leaves another concurrent reuse and the session usable" do
    observer = self()
    host = host(:concurrent)
    key = key()
    config = config(observer, :blocked)
    assert {:ok, first} = open(host, key, config)

    start_supervised!(
      {Task, fn -> send(observer, {:first, open(host, key, config, deadline: now() + 250)}) end},
      id: :first
    )

    assert_receive {:authorization_started, first_worker}, 1_000

    start_supervised!(
      {Task, fn -> send(observer, {:second, open(host, key, config)}) end},
      id: :second
    )

    assert_receive {:authorization_started, second_worker}, 1_000
    refute first_worker == second_worker
    assert_receive {:first, {:error, :connection_failed}}, 750
    send(second_worker, :release_authorization)
    assert_receive {:second, {:ok, ^first}}, 750
    assert {:ok, ^first} = Connections.lookup(key, owner: host)
  end

  test "reused readiness shares the opener's absolute deadline" do
    observer = self()
    host = host(:readiness)
    key = key()
    config = config(observer, :ready)
    assert {:ok, first} = open(host, key, config)
    client = Connection.client(first)
    :ok = :sys.suspend(client)

    caller =
      start_supervised!(
        {Task,
         fn ->
           send(observer, {:reuse_result, open(host, key, config, deadline: now() + 150)})
         end}
      )

    try do
      assert_receive {:authorization_started, _worker}, 1_000
      assert_receive {:reuse_result, {:error, :connection_failed}}, 750
    after
      :sys.resume(client)
      Process.exit(caller, :kill)
    end

    assert {:ok, ^first} = Connections.lookup(key, owner: host)
  end

  test "a retired session cannot start reuse credential resolution" do
    observer = self()
    host = host(:retired)
    key = key()
    config = config(observer, :ready)
    assert {:ok, first} = open(host, key, config)

    assert {:ok, _permission} =
             SessionLifecycle.begin_close(
               Connection.owner(first),
               Connection.client(first),
               self(),
               now() + 5_000
             )

    assert {:error, :connection_failed} = open(host, key, config)
    refute_receive {:authorization_started, _worker}, 50
  end

  test "a successful callback cannot publish after the original deadline" do
    observer = self()
    host = host(:late_result)
    key = key()
    config = config(observer, :blocked)
    assert {:ok, first} = open(host, key, config)

    caller =
      start_supervised!(
        {Task,
         fn ->
           deadline = now() + 300
           Process.send_after(observer, :deadline_passed, 320)
           send(observer, {:reuse_result, open(host, key, config, deadline: deadline)})
         end}
      )

    assert_receive {:authorization_started, worker}, 1_000
    reference = Process.monitor(worker)
    :erlang.suspend_process(caller)

    try do
      send(worker, :release_authorization)
      assert_receive {:DOWN, ^reference, :process, ^worker, _reason}, 1_000
      assert_receive :deadline_passed, 1_000
    after
      :erlang.resume_process(caller)
    end

    assert_receive {:reuse_result, {:error, :connection_failed}}, 750
    assert {:ok, ^first} = Connections.lookup(key, owner: host)
  end

  for cancellation <- [:deadline, :caller_death] do
    @cancellation cancellation

    test "delayed helper admission rejects #{cancellation} before authorization" do
      observer = self()
      host = host(:delayed)
      key = key()
      config = config(observer, :ready)
      assert {:ok, first} = open(host, key, config)

      [{transport, _metadata}] =
        Registry.lookup(
          Vxpipe.MCP.ConnectionRegistry,
          {:transport_workers, Connection.owner(first)}
        )

      :ok = :sys.suspend(transport)

      caller =
        start_supervised!(
          {Task,
           fn ->
             receive do: (:open -> :ok)
             send(observer, {:reuse_result, open(host, key, config, deadline: now() + 150)})
           end}
        )

      :erlang.trace(caller, true, [:send, :set_on_spawn])
      send(caller, :open)

      try do
        assert_receive {:trace, _admission, :send, {:"$gen_call", _from, {:start_child, _child}},
                        ^transport},
                       1_000

        case @cancellation do
          :deadline ->
            assert_receive {:reuse_result, {:error, :connection_failed}}, 750

          :caller_death ->
            reference = Process.monitor(caller)
            Process.exit(caller, :kill)
            assert_receive {:DOWN, ^reference, :process, ^caller, :killed}
        end
      after
        :sys.resume(transport)
        Process.exit(caller, :kill)
      end

      _ = :sys.get_state(transport)
      refute_receive {:authorization_started, _worker}, 50
      assert {:ok, ^first} = Connections.lookup(key, owner: host)
    end
  end

  defp host(id) do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:reuse_host, make_ref()}}}

    start_supervised!(
      Supervisor.child_spec({DynamicSupervisor, strategy: :one_for_one, name: name},
        restart: :temporary
      ),
      id: id
    )
  end

  defp open(host, key, config, opts \\ []) do
    Connections.open(key, config, Keyword.merge([owner: host, runtime: ReadyClientRuntime], opts))
  end

  defp config(observer, mode) do
    {:ok, authentication} =
      RuntimeAuthProvider.init(%{
        tenant: "reuse-fixture",
        connection_id: "connection",
        generation: 1,
        auth_method: "none",
        endpoint: "https://mcp.example.test/mcp",
        resolver:
          {Vxpipe.MCP.Test.RuntimeAuthFixture,
           {observer,
            fn ->
              send(observer, {:authorization_started, self()})
              if mode == :blocked, do: receive(do: (:release_authorization -> :ok))
              send(observer, :authorization_completed)
              {:ok, %{auth_method: "none", headers: []}}
            end}}
      })

    [endpoint: "https://mcp.example.test/mcp", runtime_authentication: authentication]
  end

  defp key do
    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "reuse-fixture",
        integration_id: "reuse-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    key
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp preserves_session?(cancellation), do: cancellation in [:deadline, :caller_death]
end
