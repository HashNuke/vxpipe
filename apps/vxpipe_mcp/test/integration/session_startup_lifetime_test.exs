defmodule Vxpipe.MCP.SessionStartupLifetimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    Connection,
    ConnectionKey,
    ConnectionNames,
    Connections,
    ReadyClientRuntime,
    RuntimeAuthProvider,
    SessionHTTPFixture
  }

  @moduletag :integration
  @moduletag :capture_log
  @moduletag timeout: 15_000

  for stage <- [:authorization, :dns],
      retirement <- [
        :caller_death,
        :owner_stop,
        :owner_death,
        :session_death,
        :guard_death,
        :deadline
      ] do
    @stage stage
    @retirement retirement

    test "#{retirement} cancels initialization blocked in #{stage}" do
      observer = self()
      server = start_supervised!({SessionHTTPFixture, owner: observer})
      owner = session_owner()
      key = key()
      other_owner = session_owner()
      {other_config, _options} = blocked_configuration(server, key, :ready)
      assert {:ok, other} = Connections.open_loopback_test(key, other_config, owner: other_owner)
      assert_receive {:session_http_session, other_session}, 1_000
      assert_receive :session_http_initialized, 1_000
      assert_receive {:session_http_held, :get, _other_peer}, 1_000
      {config, runtime_options} = blocked_configuration(server, key, @stage)

      deadline =
        System.monotonic_time(:millisecond) +
          if(@retirement == :deadline, do: 1_000, else: 30_000)

      caller =
        start_supervised!(
          {Task,
           fn ->
             result =
               Connections.open_loopback_test(key, config,
                 owner: owner,
                 deadline: deadline,
                 runtime_options: runtime_options
               )

             send(observer, {:startup_result, result})
           end},
          id: :opener
        )

      assert_receive {:startup_blocked, blocked_worker}, 1_000
      {:ok, client} = ConnectionNames.lookup(:client, key, owner)

      try do
        {:ok, integration} = ConnectionNames.lookup(:owner, key, owner)

        [{transport, _value}] =
          Registry.lookup(Vxpipe.MCP.ConnectionRegistry, {:transport_workers, integration})

        monitors =
          [client, blocked_worker, integration, transport]
          |> Enum.uniq()
          |> Map.new(&{&1, Process.monitor(&1)})

        retire(@retirement, caller, owner, integration)
        timeout = if @retirement == :deadline, do: 1_500, else: 300

        for {pid, reference} <- monitors do
          assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, timeout
        end

        send(blocked_worker, :release_startup)
        refute_receive {:session_http_session, _unexpected_session}, 100
        refute_receive {:startup_result, {:ok, _late_handle}}, 100

        assert {:ok, %{"content" => [%{"text" => ^other_session}]}} =
                 Vxpipe.MCP.ExMCPClient.call_tool(Connection.client(other), "echo", %{}, 1_000)

        assert Connections.owned_by?(other, other_owner)
      after
        Process.exit(blocked_worker, :kill)
        Process.exit(client, :kill)
      end
    end
  end

  test "an already-expired absolute startup deadline cannot create a session" do
    owner = session_owner()

    assert {:error, :connection_failed} =
             Connections.open(key(), [endpoint: "https://mcp.example.test/mcp"],
               owner: owner,
               deadline: System.monotonic_time(:millisecond) - 1,
               runtime: ReadyClientRuntime
             )

    assert DynamicSupervisor.count_children(owner).active == 0
  end

  for cancellation <- [:queued_deadline, :expired_admission, :dead_opener] do
    @cancellation cancellation

    test "#{cancellation} cannot start a client through a delayed host" do
      owner = session_owner()
      observer = self()
      key = key()
      :ok = :sys.suspend(owner)

      caller =
        start_supervised!(
          {Task,
           fn ->
             receive do
               :open ->
                 deadline = System.monotonic_time(:millisecond) + 200
                 Process.send_after(observer, :queued_deadline_reached, 220)

                 result =
                   Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
                     owner: owner,
                     deadline: deadline,
                     runtime: ReadyClientRuntime,
                     runtime_options: [test_start_observer: observer]
                   )

                 send(observer, {:queued_start_result, result})
             end
           end}
        )

      :erlang.trace(caller, true, [:send, :set_on_spawn])
      send(caller, :open)

      try do
        assert_receive {:trace, _sender, :send, {:"$gen_call", _from, {:start_child, _spec}},
                        ^owner},
                       1_000

        :erlang.trace(caller, false, [:all])
        queued_cancellation(@cancellation, caller)
      after
        :sys.resume(owner)
      end

      _ = :sys.get_state(owner)
      refute_receive {:ready_client_started, _late_client}, 100
      assert DynamicSupervisor.count_children(owner).active == 0
    end
  end

  for cancellation <- [:owner_death, :dns_timeout] do
    @cancellation cancellation

    test "#{cancellation} removes the DNS wrapper and its linked resolver task" do
      observer = self()
      server = start_supervised!({SessionHTTPFixture, owner: observer})
      owner = session_owner()
      key = key()

      start_supervised!(
        {Task,
         fn ->
           result =
             Connections.open_loopback_test(key, [endpoint: SessionHTTPFixture.endpoint(server)],
               owner: owner,
               runtime_options: [
                 dns_timeout_ms: if(@cancellation == :dns_timeout, do: 200, else: 30_000),
                 dns_resolver: fn _host, _timeout ->
                   wrapper = self()

                   task =
                     Task.async(fn ->
                       send(observer, {:linked_dns_blocked, wrapper, self()})

                       receive do
                         :release_startup -> {:ok, [{127, 0, 0, 1}]}
                       end
                     end)

                   Task.await(task, :infinity)
                 end
               ]
             )

           send(observer, {:startup_result, result})
         end}
      )

      assert_receive {:linked_dns_blocked, wrapper, resolver}, 1_000
      monitors = Map.new([wrapper, resolver], &{&1, Process.monitor(&1)})
      if @cancellation == :owner_death, do: Process.exit(owner, :kill)

      for {pid, reference} <- monitors do
        assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, 1_000
      end

      assert_receive {:startup_result, {:error, :connection_failed}}, 1_000
      send(resolver, :release_startup)
      refute_receive {:session_http_session, _unexpected_session}, 100
    end
  end

  test "a failed DNS helper does not crash an established client" do
    server = start_supervised!({SessionHTTPFixture, owner: self()})
    mode = start_supervised!({Agent, fn -> :resolve end})
    owner = session_owner()

    assert {:ok, connection} =
             Connections.open_loopback_test(
               key(),
               [endpoint: SessionHTTPFixture.endpoint(server), use_sse: false],
               owner: owner,
               runtime_options: [
                 dns_resolver: fn _host, _timeout ->
                   case Agent.get(mode, & &1) do
                     :resolve -> {:ok, [{127, 0, 0, 1}]}
                     :fail -> exit(:synthetic_dns_failure)
                   end
                 end
               ]
             )

    assert_receive {:session_http_session, session}
    Agent.update(mode, fn _mode -> :fail end)
    client = Connection.client(connection)

    assert {:error, :outcome_unknown} =
             Vxpipe.MCP.ExMCPClient.call_tool(client, "echo", %{}, 1_000)

    Agent.update(mode, fn _mode -> :resolve end)

    assert {:ok, %{"content" => [%{"text" => ^session}]}} =
             Vxpipe.MCP.ExMCPClient.call_tool(client, "echo", %{}, 1_000)

    assert Connections.owned_by?(connection, owner)
  end

  test "the opener can exit after readiness without retiring the established session" do
    owner = session_owner()
    observer = self()

    caller =
      start_supervised!(
        {Task,
         fn ->
           result =
             Connections.open(key(), [endpoint: "https://mcp.example.test/mcp"],
               owner: owner,
               runtime: ReadyClientRuntime
             )

           send(observer, {:ready_connection, result})
         end}
      )

    reference = Process.monitor(caller)
    assert_receive {:ready_connection, {:ok, connection}}
    assert_receive {:DOWN, ^reference, :process, ^caller, _reason}
    assert Connections.owned_by?(connection, owner)

    assert {:ok, %{connection_status: :ready}} =
             ReadyClientRuntime.status(Connection.client(connection))
  end

  for cancellation <- [:requester_death, :guardian_death, :deadline] do
    @cancellation cancellation

    test "#{cancellation} removes blocked DNS work without closing the session" do
      observer = self()
      server = start_supervised!({SessionHTTPFixture, owner: observer})
      owner = session_owner()
      mode = start_supervised!({Agent, fn -> :resolve end})
      key = key()

      {:ok, authentication} =
        RuntimeAuthProvider.init(%{
          tenant: "startup-fixture",
          connection_id: key.integration_id,
          generation: 1,
          auth_method: "none",
          endpoint: "https://mcp.example.test/mcp",
          resolver:
            {Vxpipe.MCP.Test.RuntimeAuthFixture,
             {observer,
              fn ->
                if Agent.get(mode, & &1) == :block, do: send(observer, {:post_requester, self()})
                {:ok, %{auth_method: "none", headers: []}}
              end}}
        })

      assert {:ok, connection} =
               Connections.open_loopback_test(
                 key,
                 [
                   endpoint: SessionHTTPFixture.endpoint(server),
                   runtime_authentication: authentication
                 ],
                 owner: owner,
                 runtime_options: [
                   dns_timeout_ms: if(@cancellation == :deadline, do: 1_000, else: 30_000),
                   dns_resolver: fn _host, _timeout ->
                     if Agent.get(mode, & &1) == :block do
                       wrapper = self()

                       task =
                         Task.async(fn ->
                           send(observer, {:dns_wrapper, wrapper, self()})
                           block(observer)
                         end)

                       Task.await(task, :infinity)
                     end

                     {:ok, [{127, 0, 0, 1}]}
                   end
                 ]
               )

      assert_receive {:session_http_session, session}
      assert_receive {:session_http_held, :get, _peer}, 1_000
      assert_receive :session_http_initialized, 1_000
      Agent.update(mode, fn _mode -> :block end)

      start_supervised!(
        {Task,
         fn ->
           result =
             Vxpipe.MCP.ExMCPClient.call_tool(Connection.client(connection), "echo", %{}, 5_000)

           send(observer, {:tool_result, result})
         end}
      )

      assert_receive {:post_requester, post}, 1_000
      assert_receive {:dns_wrapper, dns, nested}, 1_000
      assert_receive {:startup_blocked, ^nested}, 1_000

      [{transport, _}] =
        Registry.lookup(
          Vxpipe.MCP.ConnectionRegistry,
          {:transport_workers, Connection.owner(connection)}
        )

      {:links, links} = Process.info(dns, :links)
      [guardian] = links -- [transport, nested]
      monitors = Map.new([dns, nested, guardian], &{&1, Process.monitor(&1)})

      try do
        cancel_dns(@cancellation, post, guardian)

        for {pid, reference} <- monitors do
          assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, 1_500
        end

        if @cancellation == :deadline, do: :erlang.resume_process(post)
        assert_receive {:tool_result, {:error, :outcome_unknown}}, 1_000
        Agent.update(mode, fn _mode -> :resolve end)

        assert {:ok, %{"content" => [%{"text" => ^session}]}} =
                 Vxpipe.MCP.ExMCPClient.call_tool(
                   Connection.client(connection),
                   "echo",
                   %{},
                   1_000
                 )
      after
        Enum.each([post, dns, nested, guardian], &Process.exit(&1, :kill))
      end
    end
  end

  defp cancel_dns(:requester_death, post, _guardian), do: Process.exit(post, :kill)
  defp cancel_dns(:guardian_death, _post, guardian), do: Process.exit(guardian, :kill)
  defp cancel_dns(:deadline, post, _guardian), do: :erlang.suspend_process(post)

  defp blocked_configuration(server, key, stage) do
    observer = self()

    {:ok, authentication} =
      RuntimeAuthProvider.init(%{
        tenant: "startup-fixture",
        connection_id: key.integration_id,
        generation: 1,
        auth_method: "none",
        endpoint: "https://mcp.example.test/mcp",
        resolver:
          {Vxpipe.MCP.Test.RuntimeAuthFixture,
           {observer,
            fn ->
              if stage == :authorization, do: block(observer)
              {:ok, %{auth_method: "none", headers: []}}
            end}}
      })

    runtime_options =
      if stage == :dns do
        [
          dns_timeout_ms: 30_000,
          dns_resolver: fn _host, _timeout ->
            block(observer)
            {:ok, [{127, 0, 0, 1}]}
          end
        ]
      else
        []
      end

    {[endpoint: SessionHTTPFixture.endpoint(server), runtime_authentication: authentication],
     runtime_options}
  end

  defp block(observer) do
    send(observer, {:startup_blocked, self()})

    receive do
      :release_startup -> :ok
    end
  end

  defp queued_cancellation(:queued_deadline, _caller),
    do: assert_receive({:queued_start_result, {:error, :connection_failed}}, 500)

  defp queued_cancellation(:expired_admission, _caller),
    do: assert_receive(:queued_deadline_reached, 1_000)

  defp queued_cancellation(:dead_opener, caller) do
    reference = Process.monitor(caller)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^reference, :process, ^caller, :killed}
  end

  defp retire(:caller_death, caller, _owner, _integration), do: Process.exit(caller, :kill)
  defp retire(:owner_death, _caller, owner, _integration), do: Process.exit(owner, :kill)
  defp retire(:session_death, _caller, _owner, integration), do: Process.exit(integration, :kill)

  defp retire(:guard_death, _caller, _owner, integration),
    do: Process.exit(GenServer.whereis(Vxpipe.MCP.SessionLifecycle.name(integration)), :kill)

  defp retire(:deadline, _caller, _owner, _integration), do: :ok

  defp retire(:owner_stop, _caller, owner, _integration) do
    start_supervised!({Task, fn -> Supervisor.stop(owner, :shutdown, 5_000) end}, id: :stopper)
  end

  defp session_owner do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:startup_test_owner, make_ref()}}}

    start_supervised!(
      Supervisor.child_spec({DynamicSupervisor, strategy: :one_for_one, name: name},
        id: make_ref(),
        restart: :temporary
      )
    )
  end

  defp key do
    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "startup-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    key
  end
end
