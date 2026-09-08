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

  test "diagnostics are disabled by default" do
    conn = get(build_conn(), "/diagnostics")

    assert response(conn, 404) == "not found"
  end

  test "enabled diagnostics remain limited to a loopback operator" do
    original = Application.fetch_env!(:vxpipe_console, :diagnostics)

    on_exit(fn -> Application.put_env(:vxpipe_console, :diagnostics, original) end)

    Application.put_env(:vxpipe_console, :diagnostics,
      enabled: true,
      access: :loopback
    )

    diagnostics_conn = get(build_conn(), "/diagnostics")
    assert html_response(diagnostics_conn, 200) =~ "Vxpipe diagnostics"

    dashboard_conn = get(build_conn(), "/diagnostics/system")
    dashboard_path = redirected_to(dashboard_conn, 302)
    assert dashboard_path == "/diagnostics/system/home"

    dashboard_page = dashboard_conn |> recycle() |> get(dashboard_path)
    assert html_response(dashboard_page, 200) =~ "Phoenix LiveDashboard"

    %Plug.Conn{} = remote_conn = build_conn()
    remote_conn = %Plug.Conn{remote_conn | remote_ip: {203, 0, 113, 9}}
    rejected_conn = get(remote_conn, "/diagnostics")

    assert response(rejected_conn, 404) == "not found"
  end
end
