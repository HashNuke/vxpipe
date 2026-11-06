defmodule Vxpipe.Console.IntegrationsDirectoryTransportTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.IntegrationsDirectory.{Request, Transport}

  @moduletag :integration

  test "the actual HTTP adapter enforces public headers and streams a directory response" do
    server =
      start_supervised!(
        {Bandit, plug: {__MODULE__, self()}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    {:ok, request} = Request.build(:categories, %{})
    # Only this local fixture bypasses the configured HTTPS-origin boundary.
    request = %{request | url: "http://127.0.0.1:#{port}/v1/categories"}

    assert {:ok, %{body: %{"items" => []}}} = Transport.fetch(request)
    assert_receive {:directory_request, version, []}
    assert version == [Request.installation_version()]
  end

  def init(owner), do: owner

  def call(conn, owner) do
    send(
      owner,
      {:directory_request, Plug.Conn.get_req_header(conn, "x-vxpipe-version"),
       Plug.Conn.get_req_header(conn, "authorization")}
    )

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, JSON.encode!(%{"items" => []}))
  end
end
