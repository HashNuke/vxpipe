defmodule Vxpipe.MCP.RuntimeAuthPrivacyTest do
  use ExUnit.Case, async: false
  alias Vxpipe.MCP.{ConnectionKey, Connections, RuntimeAuthProvider}
  alias Vxpipe.MCP.Test.RuntimeAuthFixture

  @markers ["synthetic-runtime-bearer-marker", "synthetic-runtime-header-marker"]

  setup do
    :ok =
      :logger.add_handler(:mcp_runtime_auth_capture, Vxpipe.MCP.CheckLogCapture, %{
        config: %{owner: self()}
      })

    on_exit(fn -> :logger.remove_handler(:mcp_runtime_auth_capture) end)
    :ok
  end

  test "SSE credential rejection cannot report cached headers or begin DNS" do
    owner = self()
    auth = revoked_auth()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        start_supervised!(
          {Task,
           fn ->
             Process.flag(:trap_exit, true)

             {:ok, stream} =
               ExMCP.Transport.SSEClient.start_link(
                 url: "https://mcp.example.test/mcp",
                 reconnect: false,
                 headers: headers(),
                 headers_provider: fn ->
                   send(owner, {:awaiting_rejection, self()})

                   receive do
                     :reject -> RuntimeAuthProvider.get_token(auth)
                   end
                 end,
                 dns_resolver: fn _, _ ->
                   send(owner, :unexpected_dns)
                   {:error, :nxdomain}
                 end
               )

             receive do
               {:EXIT, ^stream, _} -> send(owner, :stream_retired)
             end
           end}
        )

        assert_receive {:awaiting_rejection, stream}, 1_000
        monitor = Process.monitor(stream)
        on_exit(fn -> Process.exit(stream, :kill) end)
        send(stream, :reject)
        assert_receive {:DOWN, ^monitor, :process, ^stream, _}, 1_000
        assert_receive :stream_retired, 1_000
      end)

    refute_received :unexpected_dns
    assert_private(log)
  end

  test "credential rejection during supervised runtime startup cannot report private headers" do
    owner = self()

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "tenant",
        integration_id: "runtime-privacy",
        credential_generation: "1"
      )

    config = [
      endpoint: "https://mcp.example.test/mcp",
      authentication: [type: :custom_headers, headers: headers()],
      runtime_authentication: revoked_auth()
    ]

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :connection_failed} =
                 Connections.open(key, config,
                   runtime_options: [
                     dns_resolver: fn _, _ ->
                       send(owner, :unexpected_dns)
                       {:error, :nxdomain}
                     end
                   ]
                 )
      end)

    assert Connections.lookup(key) == :error
    refute_received :unexpected_dns
    assert_private(log)
  end

  @tag :integration
  test "revoked credentials on a live stateless HTTP client return an error without leaking headers" do
    owner = self()
    server = start_supervised!({Vxpipe.MCP.CheckHTTPFixture, owner: owner, session: false})

    credentials =
      start_supervised!(
        {Agent,
         fn -> {:ok, %{auth_method: "oauth", token: "synthetic-runtime-bearer-marker"}} end}
      )

    {:ok, auth} =
      RuntimeAuthProvider.init(%{
        tenant: "tenant",
        connection_id: "connection",
        generation: 1,
        auth_method: "oauth",
        endpoint: "https://mcp.example.test/mcp",
        resolver: {RuntimeAuthFixture, {owner, fn -> Agent.get(credentials, & &1) end}}
      })

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "tenant",
        integration_id: "runtime-privacy-live",
        credential_generation: "1"
      )

    config = [
      endpoint: Vxpipe.MCP.CheckHTTPFixture.endpoint(server),
      authentication: [
        type: :custom_headers,
        headers: [{"x-workspace", "synthetic-runtime-header-marker"}]
      ],
      runtime_authentication: auth
    ]

    on_exit(fn -> Connections.close(key) end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, connection} = Connections.open_loopback_test(key, config)
        assert_receive {:check_http, "initialize", _}
        assert_receive {:check_http, "notifications/initialized", _}
        Agent.update(credentials, fn _ -> {:error, :revoked} end)

        result =
          try do
            Vxpipe.MCP.ExMCPClient.call_tool(
              Vxpipe.MCP.Connection.client(connection),
              "lookup",
              %{},
              1_000
            )
          catch
            :exit, reason -> {:exited, reason}
          end

        send(owner, {:request_result, result})
        Connections.close(connection)
      end)

    refute_received {:check_http, "tools/call", _}
    assert_private(log)
    assert_receive {:request_result, {:error, :not_submitted}}
  end

  defp revoked_auth do
    {:ok, auth} =
      RuntimeAuthProvider.init(%{
        tenant: "tenant",
        connection_id: "connection",
        generation: 1,
        auth_method: "oauth",
        endpoint: "https://mcp.example.test/mcp",
        resolver: {RuntimeAuthFixture, {self(), {:error, :revoked}}}
      })

    auth
  end

  defp headers do
    [
      {"authorization", "Bearer synthetic-runtime-bearer-marker"},
      {"x-workspace", "synthetic-runtime-header-marker"}
    ]
  end

  defp assert_private(log) do
    Logger.flush()
    encoded = :erlang.term_to_binary(collect_logs())
    leaked = Enum.filter(@markers, fn marker -> log =~ marker or encoded =~ marker end)
    assert leaked == []
  end

  defp collect_logs do
    receive do
      {:check_log, event} -> [event | collect_logs()]
    after
      0 -> []
    end
  end
end
