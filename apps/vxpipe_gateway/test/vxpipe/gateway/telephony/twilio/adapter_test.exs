defmodule Vxpipe.Gateway.Telephony.Twilio.AdapterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Adapter, Event, Webhook}
  alias Vxpipe.Gateway.Telephony.Twilio.Adapter, as: TwilioAdapter

  @account_sid "AC00000000000000000000000000000000"
  @call_sid "CA00000000000000000000000000000000"
  @auth_token "twilio-test-auth-token"
  @url "https://voice.example.test/api/telephony/twilio/primary/voice"
  @received_at DateTime.to_unix(~U[2026-09-11 16:00:00Z])

  test "verifies and normalizes an incoming Twilio Voice webhook" do
    parameters = incoming_parameters()
    body = URI.encode_query(parameters)

    webhook = %Webhook{
      headers: %{"x-twilio-signature" => signature(parameters)},
      body: body,
      received_at: @received_at,
      url: @url
    }

    assert {:ok,
            %Event{
              kind: :incoming,
              provider: :twilio,
              provider_event_id: "#{@call_sid}:incoming",
              provider_connection_id: @account_sid,
              provider_call_control_id: @call_sid,
              provider_call_leg_id: @call_sid,
              provider_call_session_id: nil,
              occurred_at: ~U[2026-09-11 16:00:00Z],
              from: "+15550001001",
              to: "+15550001000"
            }} =
             Adapter.ingest_webhook(
               TwilioAdapter,
               [account_sid: @account_sid, auth_token: @auth_token],
               webhook
             )
  end

  test "rejects a valid signature after the form body is changed" do
    parameters = incoming_parameters()

    webhook = %Webhook{
      headers: %{"x-twilio-signature" => signature(parameters)},
      body: URI.encode_query(%{parameters | "From" => "+15550009999"}),
      received_at: @received_at,
      url: @url
    }

    assert {:error, :invalid_twilio_webhook_authentication} =
             Adapter.ingest_webhook(
               TwilioAdapter,
               [account_sid: @account_sid, auth_token: @auth_token],
               webhook
             )
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

  defp signature(parameters) do
    signed =
      parameters
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce(@url, fn {key, value}, input -> input <> key <> value end)

    :crypto.mac(:hmac, :sha, @auth_token, signed)
    |> Base.encode64()
  end
end
