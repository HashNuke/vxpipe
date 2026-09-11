defmodule Vxpipe.Gateway.HTTP.TwilioCallbacksTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, IngressIdentity}
  alias Vxpipe.Gateway.Telephony.Twilio.PublicEndpoint
  alias Vxpipe.Gateway.TestTelephonyIngress

  @account_sid "AC00000000000000000000000000000000"
  @auth_token "twilio-test-auth-token"
  @call_sid "CA00000000000000000000000000000000"
  @ingress_key "ingress_twilio_primary"
  @leg_id "tleg_outbound_123"
  @received_at DateTime.to_unix(~U[2026-09-11 17:00:00Z])

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
      Endpoint.init(
        telephony: [
          enabled: true,
          clock: fn -> @received_at end,
          handler: {TestTelephonyIngress, self()},
          services: [service_options]
        ]
      )

    {:ok, service} = ConfiguredService.new(service_options)
    %{endpoint: endpoint, public_url: PublicEndpoint.event_url(service, @leg_id)}
  end

  test "authenticates and correlates an outbound progress callback", context do
    parameters = %{
      "AccountSid" => @account_sid,
      "CallSid" => @call_sid,
      "CallStatus" => "initiated",
      "Direction" => "outbound-api",
      "From" => "+15550001000",
      "SequenceNumber" => "0",
      "To" => "+15550001001"
    }

    conn = request(context, @leg_id, parameters, signature(context.public_url, parameters))

    assert conn.status == 200
    assert conn.resp_body == "ok"

    assert_receive {:telephony_event, %IngressIdentity{provider: :twilio},
                    %Event{
                      kind: :outgoing,
                      provider: :twilio,
                      provider_event_id: "#{@call_sid}:status:0",
                      provider_call_control_id: @call_sid,
                      provider_call_leg_id: @call_sid,
                      provider_call_session_id: nil,
                      leg_id: @leg_id,
                      sequence_number: 0,
                      from: "+15550001000",
                      to: "+15550001001"
                    }}
  end

  test "normalizes an asynchronous machine result for the same leg", context do
    parameters = %{
      "AccountSid" => @account_sid,
      "AnsweredBy" => "machine_start",
      "CallSid" => @call_sid,
      "MachineDetectionDuration" => "1840"
    }

    conn = request(context, @leg_id, parameters, signature(context.public_url, parameters))

    assert conn.status == 200

    assert_receive {:telephony_event, %IngressIdentity{},
                    %Event{
                      kind: :answering_machine,
                      provider_event_id: "#{@call_sid}:amd:machine_start",
                      provider_call_leg_id: @call_sid,
                      leg_id: @leg_id,
                      answering_machine: :machine
                    }}
  end

  test "normalizes a terminal status without exposing provider details", context do
    parameters = %{
      "AccountSid" => @account_sid,
      "CallSid" => @call_sid,
      "CallStatus" => "busy",
      "Direction" => "outbound-api",
      "From" => "+15550001000",
      "SequenceNumber" => "3",
      "To" => "+15550001001"
    }

    conn = request(context, @leg_id, parameters, signature(context.public_url, parameters))

    assert conn.status == 200

    assert_receive {:telephony_event, %IngressIdentity{},
                    %Event{
                      kind: :ended,
                      provider_event_id: "#{@call_sid}:status:3",
                      sequence_number: 3,
                      end_reason: :busy
                    }}
  end

  test "rejects a callback signed for another leg path before dispatch", context do
    parameters = %{
      "AccountSid" => @account_sid,
      "CallSid" => @call_sid,
      "CallStatus" => "initiated",
      "Direction" => "outbound-api",
      "From" => "+15550001000",
      "SequenceNumber" => "0",
      "To" => "+15550001001"
    }

    conn =
      request(
        context,
        "tleg_outbound_other",
        parameters,
        signature(context.public_url, parameters)
      )

    assert conn.status == 401
    refute_receive {:telephony_event, _identity, _event}
  end

  test "acknowledges an authenticated callback outside the consumed lifecycle", context do
    parameters = %{
      "AccountSid" => @account_sid,
      "CallSid" => @call_sid,
      "CallStatus" => "queued",
      "Direction" => "outbound-api",
      "From" => "+15550001000",
      "SequenceNumber" => "0",
      "To" => "+15550001001"
    }

    conn = request(context, @leg_id, parameters, signature(context.public_url, parameters))

    assert conn.status == 200
    assert conn.resp_body == "ok"
    refute_receive {:telephony_event, _identity, _event}
  end

  defp request(context, leg_id, parameters, signature) do
    :post
    |> conn(
      "/api/telephony/twilio/#{@ingress_key}/events/#{leg_id}",
      URI.encode_query(parameters)
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-twilio-signature", signature)
    |> Endpoint.call(context.endpoint)
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
