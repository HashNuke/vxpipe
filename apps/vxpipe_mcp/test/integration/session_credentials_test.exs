defmodule Vxpipe.MCP.SessionCredentialsTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    CheckHTTPFixture,
    Connection,
    ConnectionKey,
    Connections,
    ReadyClientRuntime,
    RuntimeAuthProvider
  }

  alias Vxpipe.MCP.Test.RuntimeAuthFixture

  @moduletag :integration
  @moduletag :capture_log

  for path <- [:initial_transport, :reuse] do
    @path path
    test "#{path} passes the exact session identity to its credential resolver" do
      host = Vxpipe.MCP.Test.SessionHost.start!()
      server = start_supervised!({CheckHTTPFixture, owner: self(), session: false})

      {:ok, auth} =
        RuntimeAuthProvider.init(%{
          tenant: "tenant",
          connection_id: "connection",
          generation: 1,
          auth_method: "none",
          endpoint: "https://mcp.example.test/mcp",
          resolver: {RuntimeAuthFixture, {self(), {:ok, %{auth_method: "none", headers: []}}}}
        })

      {:ok, key} =
        ConnectionKey.new(
          scope: :tenant,
          tenant_id: "tenant",
          integration_id: "credentials-#{System.unique_integer([:positive])}",
          credential_generation: "1"
        )

      config = [endpoint: CheckHTTPFixture.endpoint(server), runtime_authentication: auth]

      opts =
        if @path == :reuse, do: [owner: host, runtime: ReadyClientRuntime], else: [owner: host]

      assert {:ok, connection} = Connections.open_loopback_test(key, config, opts)
      session = Connection.owner(connection)

      if @path == :reuse,
        do: assert({:ok, ^connection} = Connections.open_loopback_test(key, config, opts))

      try do
        assert_receive {:resolved_owner, ^session}
      after
        Connections.close(connection)
      end
    end
  end
end
