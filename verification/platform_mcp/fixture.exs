defmodule Vxpipe.PlatformMCPFixture do
  @moduledoc false

  alias Vxpipe.Calls.{Principal, Tenant}
  alias Vxpipe.Console.Endpoint, as: ConsoleEndpoint
  alias Vxpipe.Gateway.HTTP.{Endpoint, Mount}

  @key "MCPFIXTURE000001"

  def run([port, ttl]) do
    for application <- [:ex_mcp, :bandit, :phoenix_live_view] do
      {:ok, _started} = Application.ensure_all_started(application)
    end

    # This VM belongs exclusively to acceptance. Use the dependency's public
    # supervision/start options; never mutate a running test suite's manager.
    :ok = Supervisor.terminate_child(ExMCP.Supervisor, ExMCP.SessionManager)
    :ok = Supervisor.delete_child(ExMCP.Supervisor, ExMCP.SessionManager)

    {:ok, _manager} =
      Supervisor.start_child(
        ExMCP.Supervisor,
        {ExMCP.SessionManager,
         session_ttl_seconds: String.to_integer(ttl), cleanup_interval_ms: 25}
      )

    mcp = [
      enabled: true,
      allowed_hosts: ["127.0.0.1"],
      allow_loopback_http: true,
      authentication: {__MODULE__, :fixture},
      call_options: [admin_repository: {__MODULE__, :fixture}]
    ]

    children = [
      %{
        id: :credential_state,
        start: {Agent, :start_link, [fn -> false end, [name: :platform_mcp_fixture_revoked]]}
      },
      {Vxpipe.Gateway.MCP.Admission, []},
      {Phoenix.PubSub, name: Vxpipe.Console.PubSub},
      {ConsoleEndpoint, gateway_mount: Mount.init(mcp: mcp)},
      listener(:gateway, {Endpoint, mcp: mcp}, String.to_integer(port)),
      listener(:embedded, {Mount, path_prefix: "/embedded", mcp: mcp}, 0),
      listener(:console, ConsoleEndpoint, 0)
    ]

    {:ok, supervisor} =
      Supervisor.start_link(children,
        strategy: :one_for_one,
        name: Vxpipe.PlatformMCPFixture.Supervisor
      )

    addresses =
      for {id, pid, _type, _modules} <- Supervisor.which_children(supervisor),
          id in [:gateway, :embedded, :console],
          into: %{} do
        {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
        suffix = if id == :embedded, do: "/embedded/mcp", else: "/mcp"
        {id, "http://127.0.0.1:#{port}#{suffix}"}
      end

    reply(addresses)
    commands()
  end

  def authenticate(:fixture, "revocable-synthetic-key") do
    if Agent.get(:platform_mcp_fixture_revoked, & &1),
      do: {:error, :revoked_api_key},
      else: {:ok, principal("revocable")}
  end

  def authenticate(:fixture, "platform-mcp-synthetic"), do: {:ok, principal("primary")}
  def authenticate(:fixture, "other-synthetic-key"), do: {:ok, principal("other")}
  def authenticate(:fixture, _secret), do: {:error, :invalid_api_key}

  def search_tenants(:fixture, {:keys, [@key]}, "", limit, offset),
    do: {:ok, {Enum.slice([tenant()], offset, limit), 1}}

  def tenant_candidates(:fixture, {:keys, keys}, _limit),
    do: {:ok, if(@key in keys, do: [tenant()], else: [])}

  defp principal(id),
    do: %Principal{tenant_key: @key, api_key_id: id, scopes: MapSet.new([:calls])}

  defp tenant,
    do: %Tenant{
      key: @key,
      name: "Acceptance tenant",
      inserted_at: ~U[2026-10-15 00:00:00Z]
    }

  defp listener(id, plug, port),
    do:
      Supervisor.child_spec(
        {Bandit, plug: plug, ip: {127, 0, 0, 1}, port: port, startup_log: false},
        id: id
      )

  defp commands do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      line when is_binary(line) ->
        line |> JSON.decode!() |> command() |> reply()
        commands()
    end
  end

  defp command(%{"action" => "revoke"}) do
    Agent.update(:platform_mcp_fixture_revoked, fn _ -> true end)
    %{ok: true}
  end

  defp command(%{"action" => "reset"}) do
    Agent.update(:platform_mcp_fixture_revoked, fn _ -> false end)
    %{ok: true}
  end

  defp command(%{"action" => "await_expiry", "session" => session}),
    do: await_expiry(session, System.monotonic_time(:millisecond) + 5_000)

  defp await_expiry(session, deadline) do
    case ExMCP.SessionManager.get_session(session) do
      {:ok, %{status: :terminated}} ->
        %{expired: true}

      _active ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "fixture session did not expire"
        end

        receive do
        after
          25 -> await_expiry(session, deadline)
        end
    end
  end

  defp reply(value), do: IO.puts("PLATFORM_MCP " <> JSON.encode!(value))
end

Vxpipe.PlatformMCPFixture.run(System.argv())
