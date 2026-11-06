defmodule Vxpipe.Console.MCPOAuthRenewalBoundaryTest do
  use Vxpipe.Console.Test.OutboundMCPOAuthCase, async: false
  alias Vxpipe.Calls.{Administration, MCPOAuthRefresh, MCPRuntimeCredentials}
  alias Vxpipe.MCP.PreflightRunner

  setup data do
    handoff = start(data)
    assert_connected(data, authorize(data, handoff))
    id = handoff["connection_id"]
    %{id: id, before: resolve(data, id)}
  end

  test "zero capacity leaves durable grant and revision untouched", data do
    options = renewal_options(data, runner(limit: 0))
    assert {:error, :mcp_connection_busy} = refresh(data, options)
    assert resolve(data, data.id) == data.before
    refute_received {:token_request, _}
  end

  test "one held renewal rejects another tenant before its durable claim", data do
    runner = runner(limit: 1, timeout: 5_000)
    options = renewal_options(data, runner, :hold)
    owner = self()
    start_supervised!({Task, fn -> send(owner, {:renewed, refresh(data, options)}) end})
    assert_receive {:token_request, worker}, 1_000

    {:ok, tenant, _} = Administration.bootstrap_tenant("Other renewal", [:admin], data.options)
    id = Vxpipe.Calls.PublicId.uuid()

    assert {:ok, _} =
             ConnectionStore.create_oauth(
               data.context,
               tenant.key,
               id,
               data.before.connection,
               data.before.secrets
             )

    assert {:error, :mcp_connection_busy} =
             MCPOAuthRefresh.refresh(tenant.key, id, 1, 1, renewal_options(data, runner))

    assert {:ok, unchanged} = ConnectionStore.resolve(data.context, tenant.key, id)
    assert unchanged.secrets == data.before.secrets
    refute_received {:token_request, _}
    send(worker, :release)
    assert_receive {:renewed, :ok}, 1_000
    assert resolve(data, data.id).secrets["access_token"] == "renewed-access"
  end

  for cause <- [:timeout, :caller_death] do
    test "#{cause} cancels token work and leaves a fenced grant", data do
      cause = unquote(cause)
      runner = runner(timeout: if(cause == :timeout, do: 200, else: 5_000))
      options = renewal_options(data, runner, :hold)
      owner = self()

      caller =
        start_supervised!({Task, fn -> send(owner, {:renewed, refresh(data, options)}) end})

      assert_receive {:token_request, worker}, 1_000
      monitor = Process.monitor(worker)

      if cause == :timeout do
        assert_receive {:renewed, {:error, :mcp_connection_timed_out}}, 1_000
      else
        caller_monitor = Process.monitor(caller)
        stop_supervised!(Task)
        assert_receive {:DOWN, ^caller_monitor, :process, ^caller, _}, 1_000
      end

      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
      assert_fenced(data, options)
    end
  end

  test "a queued successful token response after the deadline cannot rotate storage", data do
    runner = runner(timeout: 750)
    options = renewal_options(data, runner, :hold)
    owner = self()
    start_supervised!({Task, fn -> send(owner, {:renewed, refresh(data, options)}) end})
    assert_receive {:token_request, worker}, 1_000
    %{jobs: jobs} = :sys.get_state(runner)
    [%{task: %{pid: completion}}] = Map.values(jobs)
    monitor = Process.monitor(completion)
    :ok = :sys.suspend(runner)
    send(worker, :release)
    assert_receive {:DOWN, ^monitor, :process, ^completion, :normal}, 1_000
    Process.send_after(self(), :deadline_passed, 800)
    assert_receive :deadline_passed, 2_000
    :ok = :sys.resume(runner)
    assert_receive {:renewed, {:error, :mcp_connection_timed_out}}, 1_000
    assert_fenced(data, options)
  end

  defp assert_fenced(data, options) do
    current = resolve(data, data.id)
    assert current.secrets["access_token"] == data.before.secrets["access_token"]
    assert current.secrets["grant_revision"] == data.before.secrets["grant_revision"]
    assert is_map(current.secrets["refresh_claim"])
    deadline = current.secrets["refresh_claim"]["deadline"]
    expired = Keyword.put(options, :now, fn -> DateTime.from_unix!(deadline) end)

    assert {:error, :oauth_reconnect_required} =
             MCPRuntimeCredentials.resolve(data.tenant, data.id, 1, expired)

    refute_received {:token_request, _}
  end

  defp runner(settings) do
    tasks = start_supervised!({Task.Supervisor, name: nil}, id: :renewal_tasks)

    start_supervised!(
      {PreflightRunner, [name: nil, task_supervisor: tasks, interval: 0] ++ settings},
      id: :renewal_runner
    )
  end

  defp renewal_options(data, runner, mode \\ :immediate) do
    owner = self()

    protocol =
      data.protocol
      |> Keyword.put(:renewal_runner, runner)
      |> Keyword.put(:request_fun, fn _, _, _, _ ->
        send(owner, {:token_request, self()})

        if mode == :hold do
          receive do
            :release -> :ok
          end
        end

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "renewed-access",
            "refresh_token" => "rotated-refresh",
            "expires_in" => 300,
            "token_type" => "Bearer"
          })}}
      end)

    Keyword.put(data.options, :mcp_oauth_refresh, {Vxpipe.Console.MCPOAuthRefresh, protocol})
  end

  defp refresh(data, options),
    do: MCPOAuthRefresh.refresh(data.tenant, data.id, 1, 1, options)
end
