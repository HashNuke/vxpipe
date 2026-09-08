defmodule Vxpipe.Console.EndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Gateway.HTTP

  @endpoint Vxpipe.Console.Endpoint

  test "serves a console page and mounted gateway routes through one endpoint" do
    console_conn = get(build_conn(), "/")

    assert html_response(console_conn, 200) =~ "Vxpipe Console"

    gateway_conn = get(build_conn(), "/healthz")

    assert response(gateway_conn, 200) == "ok"
    assert Process.whereis(HTTP.Supervisor) == nil
    assert is_pid(Process.whereis(Vxpipe.Gateway.SessionSupervisor))
    assert is_pid(Process.whereis(Vxpipe.Gateway.WebRTC.ConnectionSupervisor))
  end

  test "mounted gateway API paths do not fall through to console routing" do
    conn = get(build_conn(), "/api/not-a-route")

    assert response(conn, 404) == "not found"
  end
end
