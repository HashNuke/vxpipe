defmodule Vxpipe.Console.Test.MCPRuntimeNode do
  @moduledoc "Runs saved OAuth renewal and actual ExMCP sessions in an isolated BEAM."

  alias Vxpipe.Calls.{MCPOAuthRefresh, MCPRuntimeCredentials, MCPTransportCredentials}
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer
  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, RuntimeAuthProvider}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthGrantStore}
  alias Vxpipe.Persistence.Test.MCPDatabaseNode

  def boot(repository, context, base) do
    identity = MCPDatabaseNode.boot(repository)
    Logger.configure(level: :warning)
    {:ok, _} = Application.ensure_all_started(:vxpipe_mcp)
    {:ok, _} = Application.ensure_all_started(:req)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      mcp_connection_repository: {ConnectionStore, context},
      mcp_oauth_grant_repository: {OAuthGrantStore, context},
      mcp_oauth_refresh: {Vxpipe.Console.MCPOAuthRefresh, protocol(base)}
    )

    {:ok, _} =
      DynamicSupervisor.start_child(Vxpipe.MCP.ConnectionSupervisor, %{
        id: __MODULE__,
        start: {Agent, :start_link, [fn -> %{} end, [name: __MODULE__]]}
      })

    identity
  end

  def refresh(tenant, id, revision), do: MCPOAuthRefresh.refresh(tenant, id, 1, revision)

  def start_renewal(tenant, id) do
    {:ok, caller} =
      DynamicSupervisor.start_child(
        Vxpipe.MCP.ConnectionSupervisor,
        {Task,
         fn ->
           result = refresh(tenant, id, 1)
           Agent.update(__MODULE__, &Map.put(&1, :renewal_result, result))
         end}
      )

    Agent.update(__MODULE__, &Map.put(&1, :renewal_caller, caller))
    :started
  end

  def cancel_renewal do
    caller = Agent.get(__MODULE__, & &1.renewal_caller)
    [worker] = Task.Supervisor.children(Vxpipe.MCP.OAuthRenewalTasks)
    references = monitor_all([caller, worker])
    :ok = DynamicSupervisor.terminate_child(Vxpipe.MCP.ConnectionSupervisor, caller)
    :ok = await_all(references)
    _ = :sys.get_state(Vxpipe.MCP.OAuthRenewalRunner)
    :cancelled
  end

  def restart_renewal_runner do
    caller = Agent.get(__MODULE__, & &1.renewal_caller)
    runner = Process.whereis(Vxpipe.MCP.OAuthRenewalRunner)
    tasks = Process.whereis(Vxpipe.MCP.OAuthRenewalTasks)
    [worker] = Task.Supervisor.children(tasks)
    references = monitor_all([runner, tasks, worker, caller])
    Process.exit(runner, :kill)
    :ok = await_all(references)

    children = Supervisor.which_children(Vxpipe.MCP.OAuthRenewalSupervisor)

    {Vxpipe.MCP.PreflightRunner, replacement, :worker, _} =
      List.keyfind(children, Vxpipe.MCP.PreflightRunner, 0)

    true = is_pid(replacement) and replacement != runner
    true = Process.whereis(Vxpipe.MCP.OAuthRenewalRunner) == replacement
    true = Process.whereis(Vxpipe.MCP.OAuthRenewalTasks) != tasks
    {:restarted, Agent.get(__MODULE__, & &1.renewal_result)}
  end

  def revoke(context, tenant, id), do: ConnectionStore.revoke(context, tenant, id, 1)

  def resolve(tenant, id, now),
    do: MCPRuntimeCredentials.resolve(tenant, id, 1, now: MCPDatabaseNode.clock(now))

  def open(tenant, id, base) do
    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: tenant,
        integration_id: id,
        credential_generation: "1"
      )

    {:ok, authentication} =
      RuntimeAuthProvider.init(%{
        tenant: tenant,
        connection_id: id,
        generation: 1,
        auth_method: "oauth",
        endpoint: OutboundMCPOAuthServer.resource(),
        resolver: {MCPTransportCredentials, :configured}
      })

    with {:ok, connection} <-
           Connections.open_loopback_test(key,
             endpoint: base <> "/mcp",
             reconnect: true,
             authentication: :none,
             runtime_authentication: authentication
           ) do
      client = Connection.client(connection)
      stream = :sys.get_state(client).transport_state.sse_pid
      true = is_pid(stream)
      Agent.update(__MODULE__, fn _ -> %{connection: connection, stream: stream} end)
      :ok
    end
  end

  def tool do
    connection = Agent.get(__MODULE__, & &1.connection)
    ExMCP.Client.call_tool(Connection.client(connection), "node_tool", %{}, timeout: 5_000)
  end

  def await_stream_down do
    stream = Agent.get(__MODULE__, & &1.stream)
    reference = Process.monitor(stream)

    receive do
      {:DOWN, ^reference, :process, ^stream, _} -> :down
    after
      5_000 -> :stream_still_running
    end
  end

  def close do
    %{connection: connection, stream: stream} = Agent.get(__MODULE__, & &1)
    owner = Connection.owner(connection)
    client = GenServer.whereis(Connection.client(connection))
    owner_monitor = Process.monitor(owner)
    stream_monitor = Process.monitor(stream)
    client_monitor = if is_pid(client), do: Process.monitor(client)
    # Explicit client disconnect owns remote DELETE; owner retirement is local.
    if is_pid(client), do: :ok = ExMCP.Client.disconnect(Connection.client(connection))
    :ok = Connections.close(connection)
    :ok = await_down(owner_monitor, owner)
    :ok = await_down(stream_monitor, stream)
    if client_monitor, do: :ok = await_down(client_monitor, client)
    Agent.update(__MODULE__, fn _ -> %{} end)
    :closed
  end

  defp await_down(reference, pid) do
    receive do
      {:DOWN, ^reference, :process, ^pid, _} -> :ok
    after
      5_000 -> :cleanup_timeout
    end
  end

  defp monitor_all(pids), do: Enum.map(pids, &{Process.monitor(&1), &1})

  defp await_all(references) do
    Enum.each(references, fn {reference, pid} -> :ok = await_down(reference, pid) end)
  end

  defp protocol(base) do
    [
      dns_resolver: fn "auth.example.test", _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn :post, {url, headers, type, body}, http, _ ->
        %URI{scheme: "https", host: "93.184.216.34", path: "/token"} =
          URI.parse(to_string(url))

        false = Keyword.fetch!(http, :autoredirect)
        headers = Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)

        response =
          Req.post!(base <> "/token",
            headers: [{"content-type", to_string(type)} | headers],
            body: body,
            decode_body: false,
            redirect: false,
            retry: false,
            receive_timeout: 10_000
          )

        {:ok, {{~c"HTTP/1.1", response.status, ~c"Fixture"}, [], response.body}}
      end
    ]
  end
end
