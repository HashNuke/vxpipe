defmodule Vxpipe.Gateway.HTTP.TwilioVoiceTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.IngressIdentity
  alias Vxpipe.Gateway.Telephony.Twilio.PublicEndpoint
  alias Vxpipe.Gateway.TestTelephonyIngress

  @account_sid "AC00000000000000000000000000000000"
  @auth_token "twilio-test-auth-token"
  @call_sid "CA00000000000000000000000000000000"
  @ingress_key "ingress_twilio_primary"
  @media_url "wss://voice.example.test/voice/api/telephony/twilio/ingress_twilio_primary/media/token"
  @received_at DateTime.to_unix(~U[2026-09-11 16:30:00Z])

  setup do
    service_options = [
      id: "twilio-primary",
      ingress_key: @ingress_key,
      provider: :twilio,
      account_sid: @account_sid,
      auth_token: @auth_token,
      public_base_url: "https://voice.example.test/voice",
      scope: {:tenant, "tenantkey1234567"}
    ]

    endpoint =
      Vxpipe.Gateway.TestTelephonyServiceRepository.endpoint(
        telephony: [
          enabled: true,
          clock: fn -> @received_at end,
          handler: {TestTelephonyIngress, {self(), {:ok, @media_url}}},
          services: [service_options]
        ]
      )

    {:ok, service} = Vxpipe.Gateway.Telephony.ConfiguredService.new(service_options)
    %{endpoint: endpoint, public_url: PublicEndpoint.voice_url(service)}
  end

  test "returns bidirectional stream TwiML after dispatching an authenticated incoming call",
       context do
    parameters = incoming_parameters()
    conn = request(context, parameters, signature(context.public_url, parameters))

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]

    assert conn.resp_body ==
             ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="#{@media_url}" /></Connect></Response>)

    assert_receive {:telephony_event,
                    %IngressIdentity{
                      provider: :twilio,
                      provider_connection_id: @account_sid
                    },
                    %Event{
                      kind: :incoming,
                      provider: :twilio,
                      provider_call_leg_id: @call_sid,
                      provider_call_session_id: nil
                    }}
  end

  test "rejects a changed form before dispatch", context do
    parameters = incoming_parameters()
    changed = %{parameters | "From" => "+15550009999"}
    conn = request(context, changed, signature(context.public_url, parameters))

    assert conn.status == 401
    assert conn.resp_body == "invalid webhook authentication"
    refute_receive {:telephony_event, _identity, _event}
  end

  defp request(context, parameters, signature) do
    :post
    |> conn(
      "/api/telephony/twilio/#{@ingress_key}/voice",
      URI.encode_query(parameters)
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-twilio-signature", signature)
    |> Endpoint.call(context.endpoint)
  end

  defp incoming_parameters do
    %{
      "AccountSid" => @account_sid,
      "CallSid" => @call_sid,
      "CallStatus" => "ringing",
      "Direction" => "inbound",
      "From" => "+15550001001",
      "To" => "+15550001000"
    }
  end

  defp signature(url, parameters) do
    signed =
      parameters
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce(url, fn {key, value}, input -> input <> key <> value end)

    :crypto.mac(:hmac, :sha, @auth_token, signed)
    |> Base.encode64()
  end
end
