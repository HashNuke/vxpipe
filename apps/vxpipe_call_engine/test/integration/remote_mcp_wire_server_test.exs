defmodule Vxpipe.CallEngine.RemoteMCPWireServerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.RemoteMCPWireServer

  @moduletag :integration

  test "a root health probe is not an MCP event stream" do
    server = start_supervised!({RemoteMCPWireServer, owner: self()})
    endpoint = RemoteMCPWireServer.endpoint(server)
    root = endpoint |> URI.parse() |> Map.put(:path, "/") |> URI.to_string()

    assert %{status: 404} = Req.get!(root, retry: false)
    refute_received {:remote_mcp_wire_stream, _}

    assert %{status: 200} = Req.get!(endpoint, retry: false)
    assert_receive {:remote_mcp_wire_stream, nil}
  end

  test "an RPC on another path is not an MCP invocation" do
    server = start_supervised!({RemoteMCPWireServer, owner: self()})
    endpoint = RemoteMCPWireServer.endpoint(server)
    other = endpoint |> URI.parse() |> Map.put(:path, "/other") |> URI.to_string()
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

    assert %{status: 404} = Req.post!(other, json: request, retry: false)
    refute_received {:remote_mcp_wire_request, _, _, _}
  end
end
