defmodule Vxpipe.Console.ClientAddressTest do
  use ExUnit.Case, async: true

  import Plug.Conn, only: [put_req_header: 3]
  import Plug.Test, only: [conn: 2]

  alias Vxpipe.Console.ClientAddress

  test "uses the proxy-appended forwarded address from a loopback peer" do
    conn =
      :post
      |> conn("/auth/api/login")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("x-forwarded-for", "198.51.100.1, 203.0.113.9")

    assert ClientAddress.for_throttling(conn) == "203.0.113.9"
  end

  test "ignores forwarded addresses from a non-loopback peer" do
    conn =
      :post
      |> conn("/auth/api/login")
      |> Map.put(:remote_ip, {192, 0, 2, 44})
      |> put_req_header("x-forwarded-for", "203.0.113.9")

    assert ClientAddress.for_throttling(conn) == "192.0.2.44"
  end

  test "falls back to the peer address for a missing or malformed forwarded header" do
    loopback = :post |> conn("/auth/api/login") |> Map.put(:remote_ip, {127, 0, 0, 1})

    assert ClientAddress.for_throttling(loopback) == "127.0.0.1"

    assert loopback
           |> put_req_header("x-forwarded-for", "not-an-address")
           |> ClientAddress.for_throttling() == "127.0.0.1"
  end

  test "Console OAuth keeps trusted proxy clients in independent quota buckets" do
    options = oauth_options()
    assert oauth_request(options, {127, 0, 0, 1}, "198.51.100.1").status == 200
    assert oauth_request(options, {127, 0, 0, 1}, "203.0.113.9").status == 200
    assert oauth_request(options, {127, 0, 0, 1}, "198.51.100.1").status == 429
    assert_received {:oauth_address, "198.51.100.1"}
    assert_received {:oauth_address, "203.0.113.9"}
  end

  test "Console OAuth ignores spoofed forwarding from untrusted peers" do
    options = oauth_options()
    assert oauth_request(options, {192, 0, 2, 44}, "198.51.100.1").status == 200
    assert oauth_request(options, {192, 0, 2, 44}, "203.0.113.9").status == 429
    assert_received {:oauth_address, "192.0.2.44"}
    refute_received {:oauth_address, "198.51.100.1"}
    refute_received {:oauth_address, "203.0.113.9"}
  end

  def rate_limit(:token, address) do
    send(self(), {:oauth_address, address})
    key = {__MODULE__, address}

    if Process.get(key),
      do: {:error, :rate_limited},
      else:
        (
          Process.put(key, true)
          :ok
        )
  end

  def exchange(_params, _resource),
    do: {:ok, %{access_token: "synthetic", token_type: "Bearer", expires_in: 600}}

  defp oauth_options do
    mounted = Vxpipe.Console.Endpoint.config(:gateway_mount)
    resolver = Map.get(mounted.endpoint.oauth, :client_address_resolver)

    Vxpipe.Gateway.OAuth.Endpoint.init(
      enabled: true,
      issuer: "https://auth.example.test",
      resource: "https://auth.example.test/mcp",
      allowed_hosts: ["auth.example.test"],
      backend: __MODULE__,
      client_address_resolver: resolver
    )
  end

  defp oauth_request(options, peer, forwarded) do
    Plug.Test.conn(:post, "https://auth.example.test/oauth/token", "code=synthetic")
    |> Map.put(:remote_ip, peer)
    |> put_req_header("x-forwarded-for", forwarded)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Vxpipe.Gateway.OAuth.Endpoint.call(options)
  end
end
