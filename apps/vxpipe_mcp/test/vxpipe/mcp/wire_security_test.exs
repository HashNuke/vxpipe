defmodule Vxpipe.MCP.WireSecurityTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{ConnectionKey, Connections, FaultServer}

  test "rejects a mixed DNS answer at the effective network client before connecting" do
    server = start_supervised!({FaultServer, fault: :remote_error, owner: self()})
    endpoint = String.replace(FaultServer.endpoint(server), "127.0.0.1", "localhost")

    resolver = fn "localhost", _timeout ->
      {:ok, [{127, 0, 0, 1}, {8, 8, 8, 8}]}
    end

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "wire-rebinding",
        credential_generation: "fixture"
      )

    assert {:error, :connection_failed} =
             Connections.open_loopback_test(
               key,
               [endpoint: endpoint, use_sse: false],
               runtime_options: [dns_resolver: resolver]
             )

    refute_receive {:fault_server_request, _method, _request}, 100
  end
end
