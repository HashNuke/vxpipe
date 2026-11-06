defmodule Vxpipe.MCP.CheckLifetimeTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.{CheckLifetime, ConnectionKey}

  test "expired admission cannot accept configuration or register a client" do
    key = key()
    lifetime = start_supervised!({CheckLifetime, key: key, owner: self(), deadline: now() - 1})
    monitor = Process.monitor(lifetime)
    assert_receive {:mcp_check_result, ^key, {:error, :mcp_connection_failed}}, 500
    assert_receive {:DOWN, ^monitor, :process, ^lifetime, _}, 500
    assert catch_exit(CheckLifetime.configure(key, %{client_options: []}))
    assert catch_exit(CheckLifetime.claim(key, :client))
  end

  test "expiry wins over a success queued before its deadline but handled after it" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    owner = self()
    key = key()
    deadline = now() + 150
    lifetime = start_supervised!({CheckLifetime, key: key, owner: owner, deadline: deadline})
    :ok = CheckLifetime.configure(key, %{client_options: []})

    {:ok, client} =
      Task.Supervisor.start_child(tasks, fn ->
        {:ok, _} = CheckLifetime.claim(key, :client)
        :ok = CheckLifetime.ready(key)
        send(owner, :client_ready)

        receive do
          :release -> :ok
        end
      end)

    client_monitor = Process.monitor(client)
    assert_receive :client_ready, 500

    worker =
      Task.Supervisor.async_nolink(tasks, fn ->
        {:ok, _} = CheckLifetime.claim(key, :worker)
        send(owner, :worker_ready)

        receive do
          :complete -> CheckLifetime.complete(key, {:ok, %{server_name: "late", catalog: []}})
        end
      end)

    assert_receive :worker_ready, 500
    :ok = :sys.suspend(lifetime)
    send(worker.pid, :complete)
    Process.send_after(self(), :deadline_passed, max(deadline - now(), 0) + 10)
    assert_receive :deadline_passed, 500
    :ok = :sys.resume(lifetime)
    assert {:error, :expired} = Task.await(worker, 500)
    assert_receive {:DOWN, ^client_monitor, :process, ^client, _}, 500
    assert_receive {:mcp_check_result, ^key, {:error, :mcp_connection_failed}}, 500
    refute_received {:mcp_check_result, ^key, {:ok, _}}
  end

  defp key do
    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "fixture",
        integration_id: "check-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    key
  end

  defp now, do: System.monotonic_time(:millisecond)
end
