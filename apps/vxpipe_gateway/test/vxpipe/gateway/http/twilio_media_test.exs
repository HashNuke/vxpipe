defmodule Vxpipe.Gateway.HTTP.TwilioMediaTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, MediaAdmission, MediaBinding}
  alias Vxpipe.Gateway.Telephony.Twilio.{MediaSocket, PublicEndpoint}

  @account_sid "AC00000000000000000000000000000000"
  @auth_token "twilio-test-auth-token"
  @ingress_key "ingress_twilio_primary"

  setup do
    admission = start_supervised!({MediaAdmission, name: nil})
    leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})
    binding = media_binding(leg)
    clock = fn -> 1_789_153_200 end
    service_options = service_options()

    endpoint =
      Endpoint.init(
        telephony: [
          enabled: true,
          services: [service_options],
          media_admission: admission,
          clock: clock
        ]
      )

    {:ok, service} = ConfiguredService.new(service_options)

    %{
      admission: admission,
      binding: binding,
      clock: clock,
      endpoint: endpoint,
      service: service
    }
  end

  test "authenticates the exact WSS URL before consuming its media token", context do
    assert {:ok, token} = MediaAdmission.issue(context.admission, context.binding, 60_000)
    url = PublicEndpoint.media_url(context.service, token)

    rejected = request(context, token, signature(url <> "/"))
    assert rejected.status == 401
    assert rejected.resp_body == "invalid media authentication"

    upgraded = request(context, token, signature(url))
    assert upgraded.state == :upgraded
    assert upgraded.status == 101

    assert [
             {:websocket,
              {MediaSocket, %{binding: context.binding, clock: context.clock},
               [timeout: 30_000, max_frame_size: 131_072, early_validate_upgrade: false]}}
           ] == sent_upgrades(upgraded)

    reused = request(context, token, signature(url))
    assert reused.status == 404
    assert reused.resp_body == "media socket not found"
  end

  defp request(context, token, signature) do
    :get
    |> conn("/api/telephony/twilio/#{@ingress_key}/media/#{token}")
    |> websocket_headers()
    |> put_req_header("x-twilio-signature", signature)
    |> Endpoint.call(context.endpoint)
  end

  defp websocket_headers(conn) do
    conn = %{conn | host: "voice.example.test", req_headers: [{"host", "voice.example.test"}]}

    conn
    |> put_req_header("connection", "upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16)))
    |> put_req_header("sec-websocket-version", "13")
  end

  defp service_options do
    [
      id: "twilio-primary",
      ingress_key: @ingress_key,
      scope: {:tenant, "tenantkey1234567"},
      provider: :twilio,
      account_sid: @account_sid,
      auth_token: @auth_token,
      public_base_url: "https://voice.example.test/voice"
    ]
  end

  defp media_binding(leg) do
    %MediaBinding{
      provider: :twilio,
      service_id: "twilio-primary",
      ingress_key: @ingress_key,
      tenant_id: "tenantkey1234567",
      call_id: "call-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-caller",
      provider_connection_id: @account_sid,
      provider_call_control_id: "CA00000000000000000000000000000000",
      provider_call_leg_id: "CA00000000000000000000000000000000",
      provider_call_session_id: nil,
      client_state_leg_id: "leg-1",
      leg: leg
    }
  end

  defp signature(url) do
    :crypto.mac(:hmac, :sha, @auth_token, url)
    |> Base.encode64()
  end
end
