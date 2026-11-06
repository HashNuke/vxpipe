defmodule Vxpipe.MCP.ConnectionCheckTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{
    ConnectionCheck,
    StaticConfiguration,
    ReadyClientRuntime,
    CheckProtocolFixture
  }

  test "initializes, discovers even an empty catalog and closes the transient client" do
    assert {:ok, result} =
             ConnectionCheck.run("tenant-a", config(), options({:ok, %{"tools" => []}}))

    assert result == %{server_name: "Calendar", catalog: []}
    assert_receive {:checked_client, client}
    monitor = Process.monitor(client)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}
  end

  test "failed discovery is not a successful empty catalog and still closes the client" do
    assert {:error, :mcp_connection_failed} =
             ConnectionCheck.run("tenant-a", config(), options({:error, :unavailable}))

    assert_receive {:checked_client, client}
    monitor = Process.monitor(client)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}
  end

  test "caller cancellation retires the session without relying on caller cleanup" do
    supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    opts = options(:hold)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        ConnectionCheck.run("tenant-a", config(), opts)
      end)

    assert_receive {:checked_client, client}, 1_000
    monitor = Process.monitor(client)
    Task.shutdown(task, :brutal_kill)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}, 1000
  end

  defp config do
    {:ok, configuration} =
      StaticConfiguration.new(%{
        "endpoint" => "https://mcp.example.test/mcp",
        "auth_method" => "none",
        "credentials" => %{}
      })

    configuration
  end

  defp options(result) do
    [
      runtime: ReadyClientRuntime,
      protocol: CheckProtocolFixture,
      runtime_options: [
        test_status: %{
          connection_status: :ready,
          protocol_version: "2025-11-25",
          server_info: %{"name" => "Calendar"},
          test_owner: self(),
          test_result: result
        }
      ]
    ]
  end
end
