defmodule Vxpipe.MCP.SessionReadinessTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{ConnectionKey, ConnectionNames, Connections, ControlledStatusRuntime}

  @moduletag :capture_log

  test "a failed original opener preserves a session published by a concurrent opener" do
    observer = self()
    counter = start_supervised!({Agent, fn -> 0 end})
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:publication_host, make_ref()}}}
    host = start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name})

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "publication-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    config = [endpoint: "https://mcp.example.test/mcp"]

    opts = [
      owner: host,
      runtime: ControlledStatusRuntime,
      runtime_options: [
        test_status: %{
          status_callback: fn ->
            case Agent.get_and_update(counter, &{&1, &1 + 1}) do
              0 ->
                send(observer, {:original_status, self()})
                receive do: (:fail_status -> {:error, :unavailable})

              _later ->
                {:ok, %{connection_status: :ready, protocol_version: "2025-11-25"}}
            end
          end
        }
      ]
    ]

    start_supervised!(
      {Task, fn -> send(observer, {:original, Connections.open(key, config, opts)}) end}
    )

    assert_receive {:original_status, worker}, 1_000
    assert {:ok, published} = Connections.open(key, config, opts)
    assert Connections.owned_by?(published, host)
    send(worker, :fail_status)
    assert_receive {:original, {:error, :connection_failed}}, 1_000
    assert {:ok, ^published} = Connections.lookup(key, owner: host)
  end

  for boundary <- [:status_deadline, :failure_cleanup] do
    @boundary boundary

    test "new session bounds #{@boundary} with the original deadline" do
      observer = self()
      name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:readiness_host, make_ref()}}}
      host = start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name})

      {:ok, key} =
        ConnectionKey.new(
          scope: :application,
          integration_id: "status-#{System.unique_integer([:positive])}",
          credential_generation: "1"
        )

      caller =
        start_supervised!(
          {Task,
           fn ->
             result =
               Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
                 owner: host,
                 runtime: ControlledStatusRuntime,
                 deadline: System.monotonic_time(:millisecond) + 200,
                 runtime_options: [
                   test_status: %{
                     status_callback: fn ->
                       send(observer, {:status_blocked, self()})
                       receive do: (:release_status -> {:error, :unavailable})
                     end
                   }
                 ]
               )

             send(observer, {:opening_result, result})
           end}
        )

      assert_receive {:status_blocked, worker}, 1_000
      {:ok, integration} = ConnectionNames.lookup(:owner, key, host)
      monitor = Process.monitor(integration)

      try do
        if @boundary == :failure_cleanup do
          :ok = :sys.suspend(host)
          send(worker, :release_status)
        end

        assert_receive {:opening_result, {:error, :connection_failed}}, 750
        assert_receive {:DOWN, ^monitor, :process, ^integration, _reason}, 750
      after
        if @boundary == :failure_cleanup, do: :sys.resume(host)
        Process.exit(caller, :kill)
        send(worker, :release_status)
      end
    end
  end
end
