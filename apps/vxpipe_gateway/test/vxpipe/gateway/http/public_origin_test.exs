defmodule Vxpipe.Gateway.HTTP.PublicOriginTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Gateway.HTTP.PublicOrigin

  test "public configuration distinguishes local, proxied and direct listener origins" do
    assert {:ok, "http://localhost:4000"} = PublicOrigin.resolve([])
    assert {:ok, "http://localhost:4567"} = PublicOrigin.resolve(port: "4567")
    assert {:ok, "http://[::1]:4567"} = PublicOrigin.resolve(host: "[::1]", port: "4567")

    assert {:ok, "https://voice.example.test"} =
             PublicOrigin.resolve(host: " Voice.Example.Test. ", port: "4000")

    assert {:ok, "https://voice.example.test:4443"} =
             PublicOrigin.resolve(host: "voice.example.test", port: "4443", tls: "phoenix")

    assert {:ok, "http://voice.example.test:4567"} =
             PublicOrigin.resolve(host: "voice.example.test", port: "4567", tls: "http")
  end

  test "the explicit telephony origin preserves its prefix and rejects embedded secrets" do
    assert {:ok, "https://callbacks.example.test/voice"} =
             PublicOrigin.resolve(
               host: "app.example.test",
               override: "https://callbacks.example.test/voice/"
             )

    for options <- [
          [host: "private@example.test"],
          [host: "example.test/path"],
          [host: "bad host"],
          [host: "[localhost]"],
          [host: "[::1"],
          [port: "70000"],
          [port: "not-a-port"],
          [tls: "unknown"],
          [override: "https://private@example.test"],
          [override: "http://example.test"],
          [override: "https://example.test?private=secret"]
        ] do
      assert {:error, :invalid_public_origin} = PublicOrigin.resolve(options)
    end
  end

  test "a malformed override authority is rejected instead of silently changing its port" do
    assert {:error, :invalid_public_origin} =
             PublicOrigin.resolve(override: "https://example.test:invalid-port/voice")
  end
end
