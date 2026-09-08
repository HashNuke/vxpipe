defmodule Vxpipe.Gateway.HTTP.MountTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Gateway.SessionSupervisor
  alias Vxpipe.Gateway.WebRTC.ConnectionSupervisor

  @origin "https://console.example.test"
  @mount_options Mount.init(
                   path_prefix: "/voice",
                   cors: [
                     allowed_origins: [@origin],
                     allowed_methods: ["POST", "PATCH", "OPTIONS"],
                     allowed_headers: ["content-type"],
                     allow_credentials: false
                   ]
                 )
  @root_mount_options Mount.init([])

  test "mounts the gateway at root without claiming console pages" do
    gateway_conn =
      :get
      |> conn("/healthz")
      |> Mount.call(@root_mount_options)

    assert gateway_conn.status == 200
    assert gateway_conn.halted
    assert gateway_conn.script_name == []

    console_conn =
      :get
      |> conn("/diagnostics")
      |> Mount.call(@root_mount_options)

    assert console_conn.status == nil
    refute console_conn.halted
  end

  test "mounts gateway routes under a host prefix without claiming host pages" do
    assert Process.whereis(HTTP.Supervisor) == nil
    assert is_pid(Process.whereis(SessionSupervisor))
    assert is_pid(Process.whereis(ConnectionSupervisor))

    host_conn =
      :get
      |> conn("/dashboard")
      |> Mount.call(@mount_options)

    assert host_conn.status == nil
    refute host_conn.halted

    gateway_conn =
      :get
      |> conn("/voice/healthz")
      |> Mount.call(@mount_options)

    assert gateway_conn.status == 200
    assert gateway_conn.resp_body == "ok"
    assert gateway_conn.halted
    assert gateway_conn.script_name == ["voice"]
    assert gateway_conn.path_info == ["healthz"]
  end

  test "preserves configured CORS behavior through the mounted gateway" do
    conn =
      :options
      |> conn("/voice/api/rtvi/offer")
      |> put_req_header("origin", @origin)
      |> put_req_header("access-control-request-method", "PATCH")
      |> put_req_header("access-control-request-headers", "content-type")
      |> Mount.call(@mount_options)

    assert conn.status == 204
    assert conn.halted
    assert get_resp_header(conn, "access-control-allow-origin") == [@origin]
    assert get_resp_header(conn, "access-control-allow-methods") == ["POST,PATCH,OPTIONS"]
  end

  test "claims unknown API paths as gateway 404 responses" do
    conn =
      :get
      |> conn("/voice/api/not-a-route")
      |> Mount.call(@mount_options)

    assert conn.status == 404
    assert conn.halted
  end
end
