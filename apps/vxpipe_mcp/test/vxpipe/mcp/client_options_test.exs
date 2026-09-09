defmodule Vxpipe.MCP.ClientOptionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.ClientOptions

  test "pins the supported protocol and safe transport defaults" do
    assert {:ok, options} =
             ClientOptions.build(
               endpoint: "https://mcp.example.test/rpc",
               headers: [{"authorization", "Bearer private"}]
             )

    assert options[:transport] == :http
    assert options[:url] == "https://mcp.example.test/rpc"
    assert options[:protocol_mode] == :legacy_only
    assert options[:protocol_version] == "2025-11-25"
    assert options[:retry_policy] == []
    assert options[:reconnect] == true
    assert options[:headers] == [{"authorization", "Bearer private"}]
  end

  test "rejects plaintext remote endpoints" do
    assert {:error, :https_required} =
             ClientOptions.build(endpoint: "http://mcp.example.test/rpc")
  end
end
