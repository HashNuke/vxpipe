defmodule Vxpipe.Providers.MorseCodeApi.EndpointTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.MorseCodeApi.Endpoint

  test "one normalized origin supplies HTTP and WebSocket transports" do
    assert {:ok, endpoint} = Endpoint.new("https://morse-audio.definerun.com/")
    assert endpoint.http == "https://morse-audio.definerun.com"
    assert endpoint.websocket == "wss://morse-audio.definerun.com"

    assert {:ok, local} = Endpoint.new("http://127.0.0.1:18794", allow_http?: true)
    assert local.http == "http://127.0.0.1:18794"
    assert local.websocket == "ws://127.0.0.1:18794"

    assert {:ok, container} = Endpoint.new("http://morse-api:9876/", allow_http?: true)
    assert container.websocket == "ws://morse-api:9876"

    assert {:ok, ipv6} = Endpoint.new("http://[::1]:8787", allow_http?: true)
    assert ipv6.websocket == "ws://[::1]:8787"
  end

  test "an unavailable configuration is explicit and has no default host" do
    assert {:error, :endpoint_not_configured} = Endpoint.new(nil)
    assert {:error, :invalid_endpoint} = Endpoint.new("")
    assert {:error, :invalid_endpoint} = Endpoint.new("http://127.0.0.1:8787")
  end

  test "rejects ambiguous origins without returning credential-bearing input" do
    for origin <- [
          "https://user:secret@example.com",
          "https://example.com/v1",
          "https://example.com//",
          "https://example.com?key=secret",
          "https://example.com#fragment",
          "https://example.com?",
          "https://example.com#",
          "wss://example.com",
          "file:///tmp/audio",
          "//example.com",
          "https://",
          "https://example.com:0",
          "https://example.com:65536",
          "https://example.com:-1",
          "https://example.com:abc",
          "https://example.com\\@evil.example",
          " https://example.com",
          "https://example.com\n",
          "https://example.com/%2f",
          8787,
          %{}
        ] do
      assert {:error, :invalid_endpoint} = Endpoint.new(origin, allow_http?: true)
    end
  end
end
