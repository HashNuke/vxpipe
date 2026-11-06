defmodule Vxpipe.MCP.RuntimeAuthProviderTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.RuntimeAuthProvider
  alias Vxpipe.MCP.Test.RuntimeAuthFixture

  defp config(result),
    do: %{
      tenant: "tenant",
      connection_id: "connection",
      generation: 1,
      auth_method: "oauth",
      endpoint: "https://mcp.example.test/mcp",
      resolver: {RuntimeAuthFixture, {self(), result}}
    }

  test "current OAuth token is resolved for each request with pinned identity" do
    assert {:ok, state} =
             RuntimeAuthProvider.init(
               config({:ok, %{auth_method: "oauth", token: "private-token"}})
             )

    assert {:ok, "private-token", ^state} = RuntimeAuthProvider.get_token(state)
    assert_receive {:resolved, "tenant", "connection", 1}
    refute inspect(state) =~ "private-token"

    assert {:error, :mcp_authorization_required, ^state} =
             RuntimeAuthProvider.handle_unauthorized("challenge", [], state)

    assert {:error, :mcp_authorization_required, ^state} =
             RuntimeAuthProvider.handle_forbidden("challenge", [], state)
  end

  test "resolution failure rejects actual HTTP submission before DNS or old-token fallback" do
    owner = self()
    assert {:ok, state} = RuntimeAuthProvider.init(config({:error, :revoked}))

    transport = %ExMCP.Transport.HTTP{
      use_sse: false,
      auth_provider: RuntimeAuthProvider,
      auth_provider_state: state,
      headers: [{"authorization", "Bearer old-token"}],
      dns_resolver: fn _, _ ->
        send(owner, :dns)
        {:error, :unavailable}
      end
    }

    assert {:error, :mcp_credentials_unavailable} =
             ExMCP.Transport.HTTP.send_message("{}", transport)

    refute_received :dns
  end

  test "revoked credentials block session deletion before DNS" do
    owner = self()
    {:ok, auth} = RuntimeAuthProvider.init(config({:error, :revoked}))

    transport = %ExMCP.Transport.HTTP{
      base_url: "https://mcp.example.test",
      endpoint: "/mcp",
      session_id: "session",
      protocol_version: "2025-11-25",
      auth_provider: RuntimeAuthProvider,
      auth_provider_state: auth,
      headers: [{"authorization", "Bearer old-token"}],
      dns_resolver: fn _, _ ->
        send(owner, :delete_dns)
        {:error, :unavailable}
      end
    }

    assert :ok = ExMCP.Transport.HTTP.terminate_session(transport)
    assert_receive {:resolved, "tenant", "connection", 1}
    refute_received :delete_dns
  end

  test "SSE connection checks runtime credentials before starting DNS" do
    owner = self()
    {:ok, auth} = RuntimeAuthProvider.init(config({:error, :revoked}))

    {:ok, stream, {:continue, :connect}} =
      ExMCP.Transport.SSEClient.init(
        url: "https://mcp.example.test/mcp",
        reconnect: false,
        headers: [{"authorization", "Bearer old-token"}],
        headers_provider: fn ->
          RuntimeAuthProvider.get_token(auth)
          {:error, :unreachable}
        end,
        dns_resolver: fn _, _ ->
          send(owner, :sse_dns)
          {:error, :unavailable}
        end
      )

    assert catch_exit(ExMCP.Transport.SSEClient.handle_continue(:connect, stream)) ==
             :mcp_credentials_unavailable

    refute_received :sse_dns
  end

  test "changed method or malformed token cannot reach the transport" do
    for result <- [
          {:ok, %{auth_method: "none"}},
          {:ok, %{auth_method: "oauth", token: "bad\r\nheader"}}
        ] do
      {:ok, state} = RuntimeAuthProvider.init(config(result))
      assert catch_exit(RuntimeAuthProvider.get_token(state)) == :mcp_credentials_unavailable
    end
  end

  test "static request headers are resolved only when a request is submitted" do
    config = %{
      config({:ok, %{auth_method: "basic", headers: [{"authorization", "Basic dXNlcjpwYXNz"}]}})
      | auth_method: "basic"
    }

    {:ok, state} = RuntimeAuthProvider.init(config)

    assert {:ok, [{"authorization", "Basic dXNlcjpwYXNz"}], ^state} =
             RuntimeAuthProvider.get_headers(state)

    assert_receive {:resolved, "tenant", "connection", 1}
  end

  test "the complete header provider rejects endpoint or header binding mismatches" do
    for result <- [
          %{auth_method: "oauth", token: "valid", endpoint: "https://different.example.test/mcp"},
          %{auth_method: "oauth", token: "valid", headers: [{"authorization", "Bearer stale"}]},
          %{auth_method: "oauth", token: "valid", headers: [{"host", "other.example.test"}]}
        ] do
      {:ok, state} = RuntimeAuthProvider.init(config({:ok, result}))
      assert catch_exit(RuntimeAuthProvider.get_headers(state)) == :mcp_credentials_unavailable
    end
  end

  test "static method labels cannot substitute unrelated headers for their required authorization" do
    for method <- ["bearer", "basic"] do
      configuration = %{
        config({:ok, %{auth_method: method, headers: [{"x-workspace", "value"}]}})
        | auth_method: method
      }

      {:ok, state} = RuntimeAuthProvider.init(configuration)
      assert catch_exit(RuntimeAuthProvider.get_headers(state)) == :mcp_credentials_unavailable
    end
  end

  @tag :integration
  test "HTTP session uses current credentials for initial SSE, reconnect and deletion" do
    alias Vxpipe.MCP.CumulativeSSEServer
    tokens = start_supervised!({Agent, fn -> "initial-token" end})
    server = start_supervised!({CumulativeSSEServer, owner: self()})
    resolver = fn -> {:ok, %{auth_method: "oauth", token: Agent.get(tokens, & &1)}} end

    {:ok, transport} =
      ExMCP.Transport.HTTP.connect(
        url: CumulativeSSEServer.endpoint(server),
        protocol_version: "2025-11-25",
        allowed_private_hosts: ["127.0.0.1"],
        auth_provider: {RuntimeAuthProvider, config(resolver)}
      )

    request =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

    assert {:ok, connected, _} = ExMCP.Transport.HTTP.send_message(request, transport)
    assert_receive {:cumulative_sse_authorization, "GET", ["Bearer initial-token"]}, 1_000
    assert_receive {:cumulative_sse_initial_stream, initial}, 1_000
    Agent.update(tokens, fn _ -> "renewed-token" end)
    send(initial, :close_stream)
    assert_receive {:cumulative_sse_authorization, "GET", ["Bearer renewed-token"]}, 2_000
    assert_receive {:cumulative_sse_resumed_stream, resumed, ["event-1"]}, 1_000
    Agent.update(tokens, fn _ -> "cleanup-token" end)
    assert :ok = ExMCP.Transport.HTTP.close(connected)
    assert_receive {:cumulative_sse_authorization, "DELETE", ["Bearer cleanup-token"]}, 1_000
    send(resumed, :close_stream)
  end

  @tag :integration
  test "refreshed SSE headers preserve the newest stream cursor over the initial HTTP cursor" do
    alias Vxpipe.MCP.CumulativeSSEServer
    tokens = start_supervised!({Agent, fn -> "initial-token" end})
    server = start_supervised!({CumulativeSSEServer, owner: self()})
    resolver = fn -> {:ok, %{auth_method: "oauth", token: Agent.get(tokens, & &1)}} end

    {:ok, transport} =
      ExMCP.Transport.HTTP.connect(
        url: CumulativeSSEServer.endpoint(server),
        protocol_version: "2025-11-25",
        allowed_private_hosts: ["127.0.0.1"],
        auth_provider: {RuntimeAuthProvider, config(resolver)}
      )

    transport = %{transport | last_event_id: "before-stream"}

    request =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

    assert {:ok, connected, _} = ExMCP.Transport.HTTP.send_message(request, transport)
    assert_receive {:cumulative_sse_resumed_stream, initial, ["before-stream"]}, 1_000
    send(initial, {:emit_progress, "cursor-regression"})

    for id <- ["event-3", "event-4"] do
      assert_receive {:sse_event, stream, %{id: ^id}}, 1_000
      send(stream, {:sse_event_ack, self()})
    end

    _ = :sys.get_state(connected.sse_pid)
    Agent.update(tokens, fn _ -> "renewed-token" end)
    send(initial, :close_stream)
    assert_receive {:cumulative_sse_resumed_stream, resumed, ["event-4"]}, 2_000
    assert_receive {:cumulative_sse_authorization, "GET", ["Bearer renewed-token"]}, 1_000
    assert :ok = ExMCP.Transport.HTTP.close(connected)
    send(resumed, :close_stream)
  end
end
