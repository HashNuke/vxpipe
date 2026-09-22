defmodule Vxpipe.Console.TelephonyHostGuardTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias Vxpipe.Console.TelephonyHostGuard

  setup do
    previous = Application.get_env(:vxpipe_console, :telephony_host, :missing)
    Application.put_env(:vxpipe_console, :telephony_host, "calls.example.test")

    on_exit(fn ->
      case previous do
        :missing -> Application.delete_env(:vxpipe_console, :telephony_host)
        value -> Application.put_env(:vxpipe_console, :telephony_host, value)
      end
    end)
  end

  test "public telephony host allows carrier routes and health checks" do
    for path <- [
          "/healthz",
          "/webhooks/platform/telnyx",
          "/webhooks/tenants/demo/telnyx",
          "/api/telephony/telnyx/ingress/media/token",
          "/api/telephony/twilio/ingress/voice",
          "/api/telephony/twilio/ingress/events/leg",
          "/api/telephony/twilio/ingress/media/token"
        ] do
      conn = conn(:get, path, "") |> Map.put(:host, "calls.example.test")
      assert TelephonyHostGuard.call(conn, []) == conn
    end
  end

  test "public telephony host rejects non-carrier routes" do
    conn = conn(:get, "/admin", "") |> Map.put(:host, "calls.example.test")
    response = TelephonyHostGuard.call(conn, [])

    assert response.halted
    assert response.status == 404
    assert response.resp_body == "not found"
  end

  test "other hosts retain full application access" do
    conn = conn(:get, "/admin", "") |> Map.put(:host, "console.example.ts.net")
    assert TelephonyHostGuard.call(conn, []) == conn
  end
end
