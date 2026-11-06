defmodule Vxpipe.MCP.ConnectionCheck do
  @moduledoc "Bounded, isolated initialization and catalog discovery; never invokes a tool."
  alias Vxpipe.MCP.{
    CheckLifetime,
    CheckSession,
    ClientOptions,
    ConnectionKey,
    ExMCPClient,
    ExMCPRuntime,
    StaticConfiguration
  }

  @supervisor Vxpipe.MCP.CheckSupervisor
  @timeout 10_000

  def run(tenant, %StaticConfiguration{} = configuration, options \\ []),
    do: run_profile(tenant, configuration, options, &ClientOptions.build/1)

  @doc "Isolated HTTP loopback fixture entry. Not selectable through production input."
  def run_loopback_test(tenant, %StaticConfiguration{} = configuration, options \\ []),
    do: run_profile(tenant, configuration, options, &ClientOptions.build_loopback_test/1)

  defp run_profile(tenant, configuration, options, builder) do
    deadline =
      System.monotonic_time(:millisecond) +
        min(Keyword.get(options, :timeout, @timeout), @timeout)

    with {:ok, key} <-
           ConnectionKey.new(
             scope: :tenant,
             tenant_id: tenant,
             integration_id:
               "check-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
             credential_generation: "1"
           ),
         {:ok, client_options} <- client_options(configuration, options, builder),
         {:ok, session} <-
           DynamicSupervisor.start_child(
             Keyword.get(options, :supervisor, @supervisor),
             {CheckSession, [key: key, owner: self(), deadline: deadline]}
           ) do
      try do
        lifetime = GenServer.whereis(CheckLifetime.name(key))
        monitor = Process.monitor(lifetime)

        try do
          :ok =
            CheckLifetime.configure(key, %{
              client_options: client_options,
              runtime: Keyword.get(options, :runtime, ExMCPRuntime),
              protocol: Keyword.get(options, :protocol, ExMCPClient),
              deadline: deadline
            })

          await_result(key, monitor, max(deadline - System.monotonic_time(:millisecond), 0) + 100)
        after
          Process.demonitor(monitor, [:flush])
        end
      after
        retire(session)
      end
    else
      {:error, :max_children} -> {:error, :mcp_connection_busy}
      _failed -> {:error, :mcp_connection_failed}
    end
  rescue
    _error -> {:error, :mcp_connection_failed}
  catch
    :exit, _reason -> {:error, :mcp_connection_failed}
  end

  defp await_result(key, monitor, timeout) do
    receive do
      {:mcp_check_result, ^key, result} -> result
      {:DOWN, ^monitor, :process, _pid, _reason} -> {:error, :mcp_connection_failed}
    after
      timeout -> {:error, :mcp_connection_failed}
    end
  end

  defp retire(session) do
    Supervisor.stop(session, :normal, 250)
  catch
    :exit, _reason -> Process.exit(session, :kill)
  end

  defp client_options(configuration, options, builder) do
    with {:ok, client_options} <-
           builder.(
             endpoint: configuration.endpoint,
             authentication: configuration.authentication,
             allowed_private_hosts: Keyword.get(options, :allowed_private_hosts, []),
             limits: [
               connect_timeout_ms: 3_000,
               request_timeout_ms: 5_000,
               stream_handshake_timeout_ms: 5_000
             ]
           ) do
      {:ok,
       client_options
       |> Keyword.merge(Keyword.get(options, :runtime_options, []))
       |> Keyword.put(:reconnect, false)
       |> Keyword.put(:use_sse, false)}
    end
  end
end
