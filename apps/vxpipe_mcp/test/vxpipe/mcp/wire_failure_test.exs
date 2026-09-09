defmodule Vxpipe.MCP.WireFailureTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Vxpipe.MCP.{
    Connection,
    ConnectionKey,
    Connections,
    Discovery,
    FaultServer,
    Invocation
  }

  test "maps remote and unsupported errors without exposing server diagnostics" do
    for {fault, expected} <- [remote_error: :remote_error, unsupported: :remote_error] do
      log =
        capture_log(fn ->
          assert {:error, ^expected} = invoke(fault)
        end)

      refute log =~ "fixture-private-value"
      assert request_count("tools/call") == 1
    end
  end

  test "treats malformed and wrong-id responses as unknown after one submission" do
    for fault <- [:malformed, :wrong_id] do
      _log =
        capture_log(fn ->
          assert {:error, :outcome_unknown} = invoke(fault)
        end)

      assert request_count("tools/call") == 1
    end
  end

  defp invoke(fault) do
    server = start_supervised!({FaultServer, fault: fault, owner: self()})
    endpoint = FaultServer.endpoint(server)
    {:ok, key} = connection_key(fault)

    {:ok, connection} =
      Connections.open_loopback_test(key,
        endpoint: endpoint,
        limits: [request_timeout_ms: 500]
      )

    try do
      with {:ok, catalog} <- Discovery.discover(Connection.client(connection)),
           result <-
             Invocation.call(
               Connection.client(connection),
               catalog,
               "fault_tool",
               %{},
               deadline_ms: 500
             ) do
        result
      end
    after
      Connections.close(connection)
    end
  end

  defp connection_key(fault) do
    suffix = System.unique_integer([:positive, :monotonic])

    ConnectionKey.new(
      integration_id: "wire-failure-#{fault}-#{suffix}",
      credential_generation: "fixture"
    )
  end

  defp request_count(method) do
    method
    |> collect_requests(0)
    |> tap(fn _count -> drain_other_requests() end)
  end

  defp collect_requests(method, count) do
    receive do
      {:fault_server_request, ^method} -> collect_requests(method, count + 1)
      {:fault_server_request, _other} -> collect_requests(method, count)
    after
      0 -> count
    end
  end

  defp drain_other_requests do
    receive do
      {:fault_server_request, _method} -> drain_other_requests()
    after
      0 -> :ok
    end
  end
end
