defmodule Vxpipe.MCP.OwnedOAuthExchangeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{
    Connection,
    ConnectionKey,
    Connections,
    OAuthTokenExchange,
    ReadyClientRuntime
  }

  setup do
    host = Vxpipe.MCP.Test.SessionHost.start!()

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "owned-token-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    {:ok, connection} =
      Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
        owner: host,
        runtime: ReadyClientRuntime
      )

    %{connection: connection}
  end

  test "token DNS keeps its one-second budget independently of the renewal runner", context do
    caller = held_dns(context.connection)
    assert_receive {:dns_worker, dns}, 1_000
    monitor = Process.monitor(dns)

    try do
      assert_receive {:token_result, {:error, :oauth_token_exchange_failed}}, 1_500
      assert_receive {:DOWN, ^monitor, :process, ^dns, _reason}, 500
      refute_received :token_submitted
    after
      Process.exit(caller, :kill)
      Connections.close(context.connection)
    end
  end

  test "session close removes token DNS before acknowledging teardown", context do
    caller = held_dns(context.connection)
    assert_receive {:dns_worker, dns}, 1_000
    monitor = Process.monitor(dns)

    try do
      assert :ok = Connections.close(context.connection)
      assert_receive {:DOWN, ^monitor, :process, ^dns, _reason}, 200
      send(dns, :release_dns)
      assert_receive {:token_result, {:error, :oauth_token_exchange_failed}}, 500
      refute_received :token_submitted
    after
      Process.exit(caller, :kill)
      Connections.close(context.connection)
    end
  end

  defp held_dns(connection) do
    observer = self()

    request = %{
      token_endpoint: "https://auth.example.test/token",
      client_id: "client",
      auth_method: :none,
      refresh_token: "synthetic-refresh",
      resource: "https://mcp.example.test/mcp"
    }

    options = [
      mcp_session: Connection.owner(connection),
      dns_resolver: fn _, _ ->
        send(observer, {:dns_worker, self()})
        receive do: (:release_dns -> {:ok, [{93, 184, 216, 34}]})
      end,
      request_fun: fn _, _, _, _ ->
        send(observer, :token_submitted)
        {:error, :fixture}
      end
    ]

    start_supervised!(
      {Task,
       fn ->
         send(observer, {:token_result, OAuthTokenExchange.refresh(request, options)})
       end}
    )
  end
end
