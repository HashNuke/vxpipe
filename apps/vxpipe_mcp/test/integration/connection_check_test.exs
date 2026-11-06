defmodule Vxpipe.MCP.ConnectionCheckIntegrationTest do
  use ExUnit.Case, async: true
  @moduletag :integration
  alias Vxpipe.MCP.{CheckHTTPFixture, ConnectionCheck, FaultServer, StaticConfiguration}

  @tag capture_log: true
  test "successful checks delete their remote session and never open a standalone stream" do
    server = start_supervised!({CheckHTTPFixture, owner: self()})

    assert {:ok, %{catalog: []}} =
             ConnectionCheck.run_loopback_test("tenant", http_config(server))

    assert_receive {:check_http, "DELETE", headers}, 500
    assert {"mcp-session-id", "check-fixture-session"} in headers
    refute_received {:check_http_unexpected, _}
  end

  @tag capture_log: true
  test "stalled DELETE is bounded and its underlying socket is closed" do
    server = start_supervised!({CheckHTTPFixture, owner: self(), hold: "DELETE"})
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.DeleteTasks})
    config = http_config(server)

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        ConnectionCheck.run_loopback_test("tenant", config)
      end)

    assert_receive {:check_http_held, "DELETE"}, 1_000
    assert {:ok, _} = Task.await(task, 1_000)
    assert_receive {:check_http_closed, "DELETE", {:error, :closed}}, 500
  end

  @tag capture_log: true
  test "cancelling initialization or tool discovery closes the actual POST socket" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.CancelTasks})

    for method <- ["initialize", "tools/list"] do
      server = start_supervised!({CheckHTTPFixture, owner: self(), hold: method})
      config = http_config(server)

      task =
        Task.Supervisor.async_nolink(tasks, fn ->
          ConnectionCheck.run_loopback_test("tenant", config)
        end)

      assert_receive {:check_http_held, ^method}, 1_000
      Task.shutdown(task, :brutal_kill)
      assert_receive {:check_http_closed, ^method, {:error, :closed}}, 500
    end
  end

  test "real HTTP initialization and tools discovery do not invoke any tool" do
    server = start_supervised!({FaultServer, fault: :remote_error, owner: self()})

    {:ok, config} =
      StaticConfiguration.new(%{
        "endpoint" => "https://example.test/mcp",
        "auth_method" => "none",
        "credentials" => %{}
      })

    config = %{config | endpoint: FaultServer.endpoint(server)}
    assert {:ok, result} = ConnectionCheck.run_loopback_test("tenant-a", config)
    assert result.server_name == "vxpipe-fault-fixture"
    assert [%{"name" => "fault_tool"}] = result.catalog
    assert %{"method" => "initialize"} = FaultServer.take_request("initialize")
    assert %{"method" => "tools/list"} = FaultServer.take_request("tools/list")
    refute_received {:fault_server_request, "tools/call", _}
  end

  defp http_config(server) do
    {:ok, config} =
      StaticConfiguration.new(%{
        "endpoint" => "https://example.test/mcp",
        "auth_method" => "none",
        "credentials" => %{}
      })

    %{config | endpoint: CheckHTTPFixture.endpoint(server)}
  end
end
