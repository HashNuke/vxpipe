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
    assert {:ok, token} =
             MediaAdmission.issue(context.admission, context.binding, 60_000, context.service)

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

  test "uses initialized leg auth and URL with conflicting or absent registry configuration",
       context do
    conflicting =
      Keyword.merge(service_options(),
        auth_token: "wrong-auth",
        public_base_url: "https://wrong.example.test"
      )

    for services <- [[conflicting], []] do
      endpoint =
        Endpoint.init(
          telephony: [
            enabled: true,
            media_admission: context.admission,
            clock: context.clock,
            services: services
          ]
        )

      assert {:ok, token} =
               MediaAdmission.issue(context.admission, context.binding, 60_000, context.service)

      url = PublicEndpoint.media_url(context.service, token)
      assert request(%{context | endpoint: endpoint}, token, signature(url)).status == 101
    end
  end

  test "rejects the unsigned carrier route and disabled ingress without consuming", context do
    assert {:ok, token} =
             MediaAdmission.issue(context.admission, context.binding, 60_000, context.service)

    unsigned =
      :get
      |> conn("/api/telephony/telnyx/#{@ingress_key}/media/#{token}")
      |> websocket_headers()
      |> Endpoint.call(context.endpoint)

    assert unsigned.status == 404

    disabled =
      Endpoint.init(
        telephony: [enabled: false, media_admission: context.admission, clock: context.clock]
      )

    url = PublicEndpoint.media_url(context.service, token)
    assert request(%{context | endpoint: disabled}, token, signature(url)).status == 404
    assert request(context, token, signature(url)).status == 101
  end

  test "invalid signatures cannot reserve a pending token's consumer slot", context do
    assert {:ok, token} =
             MediaAdmission.reserve(
               context.admission,
               @ingress_key,
               context.binding.leg,
               60_000,
               context.service
             )

    url = PublicEndpoint.media_url(context.service, token)
    assert request(context, token, signature(url <> "/wrong")).status == 401
    supervisor = start_supervised!({Task.Supervisor, name: nil})

    upgrade =
      Task.Supervisor.async_nolink(supervisor, fn -> request(context, token, signature(url)) end)

    assert Task.yield(upgrade, 50) == nil
    assert :ok = MediaAdmission.bind(context.admission, context.binding)
    assert {:ok, response} = Task.yield(upgrade, 1_000)
    assert response.status == 101
  end

  test "a configured registry cannot supply auth to an unconfigured reservation", context do
    assert {:ok, token} =
             MediaAdmission.reserve(context.admission, @ingress_key, context.binding.leg, 60_000)

    url = PublicEndpoint.media_url(context.service, token)
    assert request(context, token, signature(url)).status == 404

    assert {:error, :media_binding_mismatch} =
             MediaAdmission.bind(context.admission, context.binding)
  end

  test "matching aliases and accounts cannot select another tenant's media auth", context do
    other_ingress = "ingress-other"
    other_auth = "other-tenant-private-auth"
    other_tenant = "another-tenant"
    other_leg = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end}, id: :other_leg)

    {:ok, other_service} =
      ConfiguredService.new(
        Keyword.merge(service_options(),
          ingress_key: other_ingress,
          scope: {:tenant, other_tenant},
          auth_token: other_auth
        )
      )

    other_binding = %{
      context.binding
      | ingress_key: other_ingress,
        tenant_id: other_tenant,
        leg: other_leg
    }

    assert {:ok, own_token} =
             MediaAdmission.issue(context.admission, context.binding, 60_000, context.service)

    assert {:ok, other_token} =
             MediaAdmission.issue(context.admission, other_binding, 60_000, other_service)

    own_url = PublicEndpoint.media_url(context.service, own_token)
    other_url = PublicEndpoint.media_url(other_service, other_token)
    assert request(context, own_token, signature(own_url, other_auth)).status == 401
    assert request(context, other_token, signature(other_url, other_auth)).status == 404

    assert request(context, other_token, signature(other_url, other_auth), other_ingress).status ==
             101

    assert request(context, own_token, signature(own_url)).status == 101
  end

  test "an unavailable admission process returns a bounded media error", context do
    assert {:ok, token} =
             MediaAdmission.issue(context.admission, context.binding, 60_000, context.service)

    assert :ok = stop_supervised(MediaAdmission)
    url = PublicEndpoint.media_url(context.service, token)
    assert request(context, token, signature(url)).status == 503
  end

  test "admission loss after private lookup returns a safe error before upgrade", context do
    assert {:ok, token} =
             MediaAdmission.issue(context.admission, context.binding, 60_000, context.service)

    clock = fn ->
      assert :ok = stop_supervised(MediaAdmission)
      context.clock.()
    end

    endpoint =
      Endpoint.init(telephony: [enabled: true, media_admission: context.admission, clock: clock])

    url = PublicEndpoint.media_url(context.service, token)
    assert request(%{context | endpoint: endpoint}, token, signature(url)).status == 503
  end

  defp request(context, token, signature, ingress_key \\ @ingress_key) do
    :get
    |> conn("/api/telephony/twilio/#{ingress_key}/media/#{token}")
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

  defp signature(url, auth_token \\ @auth_token) do
    :crypto.mac(:hmac, :sha, auth_token, url)
    |> Base.encode64()
  end
end
