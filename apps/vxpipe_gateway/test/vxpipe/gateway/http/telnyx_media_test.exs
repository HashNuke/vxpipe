defmodule Vxpipe.Gateway.HTTP.TelnyxMediaTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.{MediaAdmission, MediaBinding}
  alias Vxpipe.Gateway.Telephony.Telnyx.MediaSocket

  setup do
    admission = start_supervised!({MediaAdmission, name: nil})
    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})
    binding = media_binding(leg)
    endpoint = Endpoint.init(telephony: [media_admission: admission])

    %{admission: admission, binding: binding, endpoint: endpoint}
  end

  test "consumes a token once and upgrades with only its exact binding", context do
    assert {:ok, token} = MediaAdmission.issue(context.admission, context.binding, 60_000)

    upgraded =
      :get
      |> conn("/api/telephony/telnyx/ingress-primary/media/#{token}")
      |> websocket_headers()
      |> Endpoint.call(context.endpoint)

    assert upgraded.state == :upgraded
    assert upgraded.status == 101

    assert [
             {:websocket,
              {MediaSocket, %{binding: context.binding},
               [timeout: 30_000, max_frame_size: 131_072, early_validate_upgrade: false]}}
           ] == sent_upgrades(upgraded)

    reused =
      :get
      |> conn("/api/telephony/telnyx/ingress-primary/media/#{token}")
      |> websocket_headers()
      |> Endpoint.call(context.endpoint)

    assert reused.status == 404
    assert reused.resp_body == "media socket not found"
  end

  test "does not consume a token for the wrong ingress or an invalid upgrade", context do
    assert {:ok, token} = MediaAdmission.issue(context.admission, context.binding, 60_000)

    wrong_ingress =
      :get
      |> conn("/api/telephony/telnyx/ingress-other/media/#{token}")
      |> websocket_headers()
      |> Endpoint.call(context.endpoint)

    assert wrong_ingress.status == 404

    invalid_upgrade =
      :get
      |> conn("/api/telephony/telnyx/ingress-primary/media/#{token}")
      |> Endpoint.call(context.endpoint)

    assert invalid_upgrade.status == 400
    assert invalid_upgrade.resp_body == "expected websocket upgrade"

    valid_upgrade =
      :get
      |> conn("/api/telephony/telnyx/ingress-primary/media/#{token}")
      |> websocket_headers()
      |> Endpoint.call(context.endpoint)

    assert valid_upgrade.state == :upgraded
  end

  defp websocket_headers(conn) do
    conn = %{conn | host: "voice.example.test", req_headers: [{"host", "voice.example.test"}]}

    conn
    |> put_req_header("connection", "upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
    |> put_req_header("sec-websocket-version", "13")
  end

  defp media_binding(leg) do
    %MediaBinding{
      provider: :telnyx,
      service_id: "primary-phone",
      ingress_key: "ingress-primary",
      tenant_id: "tenant-demo",
      call_id: "call-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-caller",
      provider_connection_id: "voice-app-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      leg: leg
    }
  end
end
