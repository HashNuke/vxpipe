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
    assert options[:max_request_bytes] == 262_144
    assert options[:max_response_bytes] == 262_144
    assert options[:max_stream_buffer_bytes] == 262_144
    assert options[:dns_timeout_ms] == 1_000
    assert options[:timeout] == 5_000
    assert options[:request_timeout] == 30_000
  end

  test "rejects plaintext remote endpoints" do
    assert {:error, :https_required} =
             ClientOptions.build(endpoint: "http://mcp.example.test/rpc")

    assert {:error, :https_required} =
             ClientOptions.build(
               endpoint: "http://127.0.0.1:4321/rpc",
               test_mode: true
             )
  end

  test "accepts validated transport and network limits" do
    assert {:ok, options} =
             ClientOptions.build(
               endpoint: "https://internal.example.test/rpc",
               limits: [
                 max_request_bytes: 4_096,
                 max_response_bytes: 8_192,
                 max_stream_buffer_bytes: 2_048,
                 dns_timeout_ms: 250,
                 connect_timeout_ms: 750,
                 request_timeout_ms: 4_000
               ],
               allowed_private_hosts: ["internal.example.test"]
             )

    assert options[:max_request_bytes] == 4_096
    assert options[:max_response_bytes] == 8_192
    assert options[:max_stream_buffer_bytes] == 2_048
    assert options[:dns_timeout_ms] == 250
    assert options[:timeout] == 750
    assert options[:request_timeout] == 4_000
    assert options[:allowed_private_hosts] == ["internal.example.test"]

    assert {:error, {:invalid_limit, :max_response_bytes}} =
             ClientOptions.build(
               endpoint: "https://mcp.example.test/rpc",
               limits: [max_response_bytes: 0]
             )
  end

  test "constructs plaintext transport only through the loopback test API" do
    assert {:ok, options} =
             ClientOptions.build_loopback_test(
               endpoint: "http://127.0.0.1:4321/rpc"
             )

    assert options[:url] == "http://127.0.0.1:4321/rpc"
    assert options[:reconnect] == false

    assert {:error, :loopback_required} =
             ClientOptions.build_loopback_test(
               endpoint: "http://mcp.example.test/rpc"
             )
  end
end
