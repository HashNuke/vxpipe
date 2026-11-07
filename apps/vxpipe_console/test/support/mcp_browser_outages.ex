defmodule Vxpipe.Console.Test.MCPBrowserOutages do
  @moduledoc "Independent, development-fixture directory and local-status fault controls."
  use Agent

  @directory_modes ~w(healthy unavailable rate_limited)
  @status_modes ~w(healthy unavailable)

  def start_link(options) do
    mode = Keyword.get(options, :directory_mode, "healthy")
    status = Keyword.get(options, :local_status, "healthy")

    with true <- mode in @directory_modes and status in @status_modes,
         {:ok, upstream} <- upstream(Keyword.get(options, :upstream)) do
      state = %{
        directory_mode: mode,
        local_status: "healthy",
        upstream: upstream,
        requests: 0,
        forwarded: 0,
        repository:
          Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
          |> Keyword.fetch(:mcp_connection_repository)
      }

      with {:ok, pid} <- Agent.start_link(fn -> state end, Keyword.take(options, [:name])) do
        :ok = local_status(pid, status)
        {:ok, pid}
      end
    else
      _ -> {:error, :invalid_browser_outage_options}
    end
  end

  def directory(state, mode) when mode in @directory_modes,
    do: Agent.update(state, &%{&1 | directory_mode: mode})

  def directory(_state, _mode), do: {:error, :invalid_browser_outage_mode}

  def local_status(state, mode) when mode in @status_modes do
    repository = Agent.get(state, & &1.repository)
    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    calls =
      case {mode, repository} do
        {"healthy", {:ok, port}} -> Keyword.put(calls, :mcp_connection_repository, port)
        _ -> Keyword.delete(calls, :mcp_connection_repository)
      end

    Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)
    Agent.update(state, &%{&1 | local_status: mode})
  end

  def local_status(_state, _mode), do: {:error, :invalid_browser_outage_mode}

  def snapshot(state),
    do: Agent.get(state, &Map.take(&1, [:directory_mode, :local_status, :requests, :forwarded]))

  def request(state) do
    Agent.get_and_update(state, fn current ->
      forwarded = if current.directory_mode == "healthy", do: 1, else: 0

      {{current.directory_mode, current.upstream},
       %{current | requests: current.requests + 1, forwarded: current.forwarded + forwarded}}
    end)
  end

  def reset_cache do
    supervisor = Vxpipe.Console.IntegrationsDirectory.Supervisor
    cache = Vxpipe.Console.IntegrationsDirectory.Cache
    :ok = Supervisor.terminate_child(supervisor, cache)
    {:ok, _} = Supervisor.restart_child(supervisor, cache)
    :ok
  end

  defp upstream(value) when is_binary(value) do
    with {:ok, uri} <- URI.new(value),
         %URI{userinfo: nil, query: nil, fragment: nil, host: host, port: port} <- uri,
         true <- is_binary(host) and host != "" and is_integer(port) and port in 1..65_535,
         true <- uri.path in [nil, "", "/"],
         true <- uri.scheme == "https" or (uri.scheme == "http" and host == "127.0.0.1") do
      {:ok, URI.to_string(%{uri | path: nil})}
    else
      _ -> :error
    end
  end

  defp upstream(_), do: :error
end
