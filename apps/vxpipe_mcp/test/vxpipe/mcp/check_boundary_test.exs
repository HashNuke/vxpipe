defmodule Vxpipe.MCP.CheckBoundaryTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    CheckFixtureRuntime,
    CheckProtocolFixture,
    ConnectionCheck,
    StaticConfiguration
  }

  setup do
    start_supervised!(
      {DynamicSupervisor, name: __MODULE__.Sessions, strategy: :one_for_one, max_children: 8}
    )

    :ok
  end

  test "owner cancellation interrupts initialization before the client acknowledges startup" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    options = options(test_init: :hold)

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        ConnectionCheck.run("tenant", config(), options)
      end)

    assert_receive {:check_initializing, client}, 1_000
    on_exit(fn -> send(client, :release) end)
    monitor = Process.monitor(client)
    Task.shutdown(task, :brutal_kill)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}, 500
  end

  test "startup failure logs do not contain credentials or endpoint query values" do
    marker = "synthetic-check-private-marker"

    {:ok, config} =
      StaticConfiguration.new(%{
        "endpoint" => "https://mcp.example.test/mcp?region=#{marker}",
        "auth_method" => "bearer",
        "credentials" => %{"token" => marker}
      })

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :mcp_connection_failed} =
                 ConnectionCheck.run("tenant", config, options(test_init: :fail))
      end)

    refute log =~ marker
  end

  test "initialization expires and releases capacity without caller cleanup" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    opts = Keyword.put(options(test_init: :hold), :timeout, 50)

    task =
      Task.Supervisor.async_nolink(tasks, fn -> ConnectionCheck.run("tenant", config(), opts) end)

    assert_receive {:check_initializing, client}, 1_000
    monitor = Process.monitor(client)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}, 500
    assert {:error, :mcp_connection_failed} = Task.await(task, 500)
    assert {:ok, _} = ConnectionCheck.run("tenant", config(), options([]))
  end

  test "eight initializing checks consume capacity while the ninth is rejected promptly" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    opts = options(test_init: :hold)

    held =
      for _ <- 1..8 do
        task =
          Task.Supervisor.async_nolink(tasks, fn ->
            ConnectionCheck.run("tenant", config(), opts)
          end)

        assert_receive {:check_initializing, client}, 500
        {task, client, Process.monitor(client)}
      end

    ninth =
      Task.Supervisor.async_nolink(tasks, fn -> ConnectionCheck.run("tenant", config(), opts) end)

    assert {:error, :mcp_connection_busy} = Task.await(ninth, 500)

    for {task, client, monitor} <- held do
      Task.shutdown(task, :brutal_kill)
      assert_receive {:DOWN, ^monitor, :process, ^client, _}, 500
    end

    assert {:ok, _} = ConnectionCheck.run("tenant", config(), options([]))
  end

  test "one initializing check does not delay another check or its cleanup" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    opts = options(test_init: :hold)

    task =
      Task.Supervisor.async_nolink(tasks, fn -> ConnectionCheck.run("tenant", config(), opts) end)

    assert_receive {:check_initializing, held}, 500
    other_opts = options([])

    other =
      Task.Supervisor.async_nolink(tasks, fn ->
        ConnectionCheck.run("tenant", config(), other_opts)
      end)

    assert {:ok, _} = Task.await(other, 500)
    Task.shutdown(task, :brutal_kill)
    monitor = Process.monitor(held)
    assert_receive {:DOWN, ^monitor, :process, ^held, _}, 500
  end

  test "post-start callback failures redact formatted and structured reports for every secret form" do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    :ok =
      :logger.add_handler(:mcp_check_fixture_capture, Vxpipe.MCP.CheckLogCapture, %{
        config: %{owner: self()}
      })

    on_exit(fn -> :logger.remove_handler(:mcp_check_fixture_capture) end)

    for {method, credentials} <- [
          {"bearer", %{"token" => "synthetic-bearer-marker"}},
          {"basic", %{"username" => "fixture", "password" => "synthetic-password-marker"}},
          {"headers",
           %{"headers" => [%{"name" => "X-Key", "value" => "synthetic-header-marker"}]}}
        ] do
      {:ok, config} =
        StaticConfiguration.new(%{
          "endpoint" => "https://mcp.example.test/mcp?region=synthetic-query-marker",
          "auth_method" => method,
          "credentials" => credentials
        })

      opts = options(test_result: :hold)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          task =
            Task.Supervisor.async_nolink(tasks, fn ->
              ConnectionCheck.run("tenant", config, opts)
            end)

          assert_receive {:checked_client, client}, 500
          send(client, :crash)
          assert {:error, :mcp_connection_failed} = Task.await(task, 1_000)
        end)

      Logger.flush()
      assert_receive {:check_log, event}, 500
      events = [event | collect_logs()]

      for marker <- [
            "synthetic-bearer-marker",
            "synthetic-password-marker",
            "synthetic-header-marker",
            "synthetic-query-marker",
            Base.encode64("fixture:synthetic-password-marker")
          ] do
        refute log =~ marker
        refute :erlang.term_to_binary(events) =~ marker
      end
    end
  end

  defp collect_logs do
    receive do
      {:check_log, event} -> [event | collect_logs()]
    after
      0 -> []
    end
  end

  defp options(extra) do
    [
      supervisor: __MODULE__.Sessions,
      runtime: CheckFixtureRuntime,
      protocol: CheckProtocolFixture,
      runtime_options: [test_owner: self()] ++ extra
    ]
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
end
