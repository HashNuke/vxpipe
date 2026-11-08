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

  test "cleanup uses only the non-renewing resolver and validates its pinned identity" do
    configuration =
      config(%{
        request: {:ok, %{auth_method: "oauth", token: "renewed-token"}},
        cleanup: {:ok, %{auth_method: "oauth", token: "current-token"}}
      })

    {:ok, state} = RuntimeAuthProvider.init(configuration)

    assert {:ok, [{"authorization", "Bearer current-token"}], ^state} =
             RuntimeAuthProvider.get_cleanup_headers(state)

    assert_receive {:cleanup_resolved, "tenant", "connection", 1}
    refute_received {:resolved, _, _, _}

    for result <- [
          {:error, :oauth_reconnect_required},
          {:ok, %{auth_method: "oauth", token: "bad\r\nheader"}},
          {:ok,
           %{auth_method: "oauth", token: "valid", endpoint: "https://other.example.test/mcp"}}
        ] do
      {:ok, state} = RuntimeAuthProvider.init(config(result))

      assert catch_exit(RuntimeAuthProvider.get_cleanup_headers(state)) ==
               :mcp_credentials_unavailable
    end
  end

  test "cleanup never falls back to a resolver that only supports ordinary requests" do
    configuration = config({:ok, %{auth_method: "oauth", token: "must-not-resolve"}})
    {_module, context} = configuration.resolver
    configuration = %{configuration | resolver: {Vxpipe.MCP.Test.RequestOnlyAuthFixture, context}}
    {:ok, state} = RuntimeAuthProvider.init(configuration)

    assert catch_exit(RuntimeAuthProvider.get_cleanup_headers(state)) ==
             :mcp_credentials_unavailable

    refute_received {:resolved, _, _, _}
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
    assert_receive {:cleanup_resolved, "tenant", "connection", 1}
    refute_received {:resolved, _, _, _}
    refute_received :delete_dns
  end

  test "DELETE skips a renewal-required grant without invoking ordinary resolution" do
    owner = self()

    {:ok, auth} =
      RuntimeAuthProvider.init(
        config(%{
          request: {:ok, %{auth_method: "oauth", token: "renewed-token"}},
          cleanup: {:error, :oauth_reconnect_required}
        })
      )

    transport = %ExMCP.Transport.HTTP{
      base_url: "https://mcp.example.test",
      endpoint: "/mcp",
      session_id: "session",
      protocol_version: "2025-11-25",
      auth_provider: RuntimeAuthProvider,
      auth_provider_state: auth,
      dns_resolver: fn _, _ ->
        send(owner, :cleanup_dns)
        {:error, :unavailable}
      end
    }

    assert :ok = ExMCP.Transport.HTTP.terminate_session(transport)
    assert_receive {:cleanup_resolved, "tenant", "connection", 1}
    refute_received {:resolved, _, _, _}
    refute_received :cleanup_dns
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

  test "owned DELETE skips a provider without the non-renewing cleanup callback" do
    owner = self()

    {:ok, auth} =
      Vxpipe.MCP.Test.RequestOnlyProvider.init(
        config({:ok, %{auth_method: "oauth", token: "renewed-token"}})
      )

    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    transport = %ExMCP.Transport.HTTP{
      base_url: "https://mcp.example.test",
      endpoint: "/mcp",
      session_id: "session",
      protocol_version: "2025-11-25",
      auth_provider: Vxpipe.MCP.Test.RequestOnlyProvider,
      auth_provider_state: auth,
      transport_supervisor: supervisor,
      dns_resolver: fn _, _ ->
        send(owner, :unsupported_cleanup_dns)
        {:error, :unavailable}
      end
    }

    assert :ok = ExMCP.Transport.HTTP.terminate_session(transport)
    refute_received {:resolved, _, _, _}
    refute_received :unsupported_cleanup_dns
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

  @tag :integration
  test "a clean SSE EOF keeps the receiver attached to the resumed session" do
    alias Vxpipe.MCP.CumulativeSSEServer
    server = start_supervised!({CumulativeSSEServer, owner: self()})

    {:ok, transport} =
      ExMCP.Transport.HTTP.connect(
        url: CumulativeSSEServer.endpoint(server),
        protocol_version: "2025-11-25",
        allowed_private_hosts: ["127.0.0.1"]
      )

    request =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

    assert {:ok, connected, _} = ExMCP.Transport.HTTP.send_message(request, transport)
    assert_receive {:cumulative_sse_initial_stream, initial}, 1_000
    owner = self()

    receiver =
      start_supervised!(
        {Task,
         fn ->
           send(owner, {:resumed_message, ExMCP.Transport.HTTP.receive_message(connected)})
         end}
      )

    await_receiver(connected.sse_pid, receiver)
    send(initial, :close_stream)
    assert_receive {:cumulative_sse_resumed_stream, resumed, ["event-1"]}, 2_000
    send(resumed, {:emit_progress, "resumed-session"})

    assert_receive {:resumed_message,
                    {:ok, %{payload: %{"method" => "notifications/progress"}}, _}},
                   2_000

    assert :ok = ExMCP.Transport.HTTP.close(connected)
    send(resumed, :close_stream)
  end

  @tag :integration
  test "credential rejection during SSE resumption unblocks the transport receiver" do
    alias Vxpipe.MCP.CumulativeSSEServer
    Process.flag(:trap_exit, true)

    tokens =
      start_supervised!({Agent, fn -> {:ok, %{auth_method: "oauth", token: "initial-token"}} end})

    server = start_supervised!({CumulativeSSEServer, owner: self()})
    resolver = fn -> Agent.get(tokens, & &1) end

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
    assert_receive {:cumulative_sse_initial_stream, initial}, 1_000
    assert_receive {:cumulative_sse_authorization, "GET", ["Bearer initial-token"]}, 1_000
    owner = self()

    receiver =
      start_supervised!(
        {Task,
         fn ->
           send(owner, {:terminal_message, ExMCP.Transport.HTTP.receive_message(connected)})
         end}
      )

    await_receiver(connected.sse_pid, receiver)
    monitor = Process.monitor(connected.sse_pid)
    Agent.update(tokens, fn _ -> {:error, :revoked} end)
    send(initial, :close_stream)
    assert_receive {:DOWN, ^monitor, :process, _, :mcp_credentials_unavailable}, 2_000
    assert_receive {:terminal_message, {:error, :connection_closed}}, 2_000
    refute_received {:cumulative_sse_authorization, "GET", _}
    assert :ok = ExMCP.Transport.HTTP.close(connected)
    refute_received {:cumulative_sse_authorization, "DELETE", _}
  end

  @tag :integration
  test "repeated clean SSE reconnects do not accumulate handshake notifications" do
    alias Vxpipe.MCP.CumulativeSSEServer
    server = start_supervised!({CumulativeSSEServer, owner: self()})
    connected = connected_stream(server)
    assert_receive {:cumulative_sse_initial_stream, initial}, 1_000
    owner = self()

    receiver =
      start_supervised!(
        {Task,
         fn ->
           Enum.reduce(1..2, connected, fn cycle, transport ->
             {:ok, _, next} = ExMCP.Transport.HTTP.receive_message(transport)
             {:ok, _, next} = ExMCP.Transport.HTTP.receive_message(next)
             {:messages, messages} = Process.info(self(), :messages)
             send(owner, {:completed_cycle, cycle, messages})

             if cycle == 1,
               do:
                 (receive do
                    :next_cycle -> :ok
                  end)

             next
           end)
         end}
      )

    await_receiver(connected.sse_pid, receiver)
    send(initial, :close_stream)
    assert_receive {:cumulative_sse_resumed_stream, first, ["event-1"]}, 2_000
    send(first, {:emit_progress, "first-cycle"})
    assert_receive {:completed_cycle, 1, messages}, 2_000
    refute Enum.any?(messages, &match?({:sse_connected, _}, &1))
    send(receiver, :next_cycle)
    send(first, :close_stream)
    assert_receive {:cumulative_sse_resumed_stream, second, ["event-4"]}, 2_000
    send(second, {:emit_progress, "second-cycle"})
    assert_receive {:completed_cycle, 2, messages}, 2_000
    refute Enum.any?(messages, &match?({:sse_connected, _}, &1))
    assert :ok = ExMCP.Transport.HTTP.close(connected)
    send(second, :close_stream)
  end

  @tag :integration
  test "a resumed GET rejecting SSE unblocks the receiver without replaying POST" do
    alias Vxpipe.MCP.CumulativeSSEServer
    server = start_supervised!({CumulativeSSEServer, owner: self(), reject_resume: true})
    connected = connected_stream(server)
    assert_receive {:cumulative_sse_initial_stream, initial}, 1_000
    assert_receive {:cumulative_sse_request, "initialize", _}, 1_000
    owner = self()

    receiver =
      start_supervised!(
        {Task,
         fn ->
           send(owner, {:unsupported_stream, ExMCP.Transport.HTTP.receive_message(connected)})
         end}
      )

    await_receiver(connected.sse_pid, receiver)
    send(initial, :close_stream)
    assert_receive :cumulative_sse_resume_rejected, 2_000
    assert_receive {:unsupported_stream, {:error, :not_supported_in_sync_mode}}, 2_000
    refute_received {:cumulative_sse_request, "initialize", _}
    assert :ok = ExMCP.Transport.HTTP.close(connected)
  end

  defp connected_stream(server) do
    {:ok, transport} =
      ExMCP.Transport.HTTP.connect(
        url: Vxpipe.MCP.CumulativeSSEServer.endpoint(server),
        protocol_version: "2025-11-25",
        allowed_private_hosts: ["127.0.0.1"]
      )

    request =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

    {:ok, connected, _} = ExMCP.Transport.HTTP.send_message(request, transport)
    connected
  end

  defp await_receiver(stream, receiver) do
    ready? =
      Enum.reduce_while(1..200, false, fn _, _ ->
        if :sys.get_state(stream).parent == receiver do
          {:halt, true}
        else
          receive do
          after
            5 -> :ok
          end

          {:cont, false}
        end
      end)

    assert ready?, "SSE receiver did not attach"
  end
end
