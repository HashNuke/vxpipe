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
end
