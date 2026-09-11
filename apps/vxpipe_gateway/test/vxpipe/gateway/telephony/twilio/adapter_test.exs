defmodule Vxpipe.Gateway.Telephony.Twilio.AdapterTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Vxpipe.CallEngine.Telephony.{
    Adapter,
    Dial,
    EndLeg,
    Event,
    LegReference,
    Submission,
    Webhook
  }

  alias Vxpipe.Gateway.Telephony.Twilio.Adapter, as: TwilioAdapter

  @account_sid "AC00000000000000000000000000000000"
  @call_sid "CA00000000000000000000000000000000"
  @auth_token "twilio-test-auth-token"
  @url "https://voice.example.test/api/telephony/twilio/primary/voice"
  @received_at DateTime.to_unix(~U[2026-09-11 16:00:00Z])

  setup :verify_on_exit!

  test "creates one outbound call with inline media TwiML and asynchronous callbacks" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"

      assert conn.request_path ==
               "/2010-04-01/Accounts/#{@account_sid}/Calls.json"

      assert get_req_header(conn, "authorization") == [
               "Basic " <> Base.encode64("#{@account_sid}:#{@auth_token}")
             ]

      fields = form_fields(conn)

      assert field(fields, "From") == "+15550001000"
      assert field(fields, "To") == "+15550001001"

      assert field(fields, "StatusCallback") ==
               "https://voice.example.test/twilio/events/leg-outbound"

      assert field(fields, "StatusCallbackMethod") == "POST"

      status_events =
        for {"StatusCallbackEvent", value} <- fields,
            do: value

      assert Enum.sort(status_events) == ["answered", "completed", "initiated", "ringing"]

      assert field(fields, "Twiml") ==
               ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="wss://voice.example.test/twilio/media/token" /></Connect></Response>)

      assert field(fields, "MachineDetection") == "Enable"
      assert field(fields, "AsyncAmd") == "true"

      assert field(fields, "AsyncAmdStatusCallback") ==
               "https://voice.example.test/twilio/events/leg-outbound"

      assert field(fields, "AsyncAmdStatusCallbackMethod") == "POST"

      conn
      |> put_status(201)
      |> Req.Test.json(%{sid: @call_sid, status: "queued"})
    end)

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: @call_sid,
              provider_call_leg_id: @call_sid,
              provider_call_session_id: nil
            }} = Adapter.dial(TwilioAdapter, command_config(), dial())
  end

  test "ends only the exact Twilio Call resource" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"

      assert conn.request_path ==
               "/2010-04-01/Accounts/#{@account_sid}/Calls/#{@call_sid}.json"

      assert form_fields(conn) == [{"Status", "completed"}]
      Req.Test.json(conn, %{sid: @call_sid, status: "completed"})
    end)

    request = %EndLeg{
      leg: %LegReference{leg_id: "leg-outbound", provider_call_control_id: @call_sid},
      reason: :transfer_cancelled
    }

    assert {:ok,
            %Submission{
              status: :accepted,
              provider_call_control_id: @call_sid
            }} = Adapter.end_leg(TwilioAdapter, command_config(), request)
  end

  test "does not retry or reinterpret an ambiguous create response" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> put_status(503)
      |> Req.Test.json(%{message: "temporarily unavailable"})
    end)

    assert {:ok, %Submission{status: :unknown, provider_call_control_id: nil}} =
             Adapter.dial(TwilioAdapter, command_config(), dial())
  end

  test "returns a bounded provider rejection without exposing its body" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> put_status(400)
      |> Req.Test.json(%{message: "private destination details"})
    end)

    assert {:error, {:twilio_command_rejected, 400}} =
             Adapter.dial(TwilioAdapter, command_config(), dial())
  end

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

  defp command_config do
    [
      account_sid: @account_sid,
      auth_token: @auth_token,
      base_url: "http://example.test/2010-04-01",
      request_options: [plug: {Req.Test, __MODULE__}]
    ]
  end

  defp dial do
    %Dial{
      leg_id: "leg-outbound",
      from: "+15550001000",
      to: "+15550001001",
      callback_url: "https://voice.example.test/twilio/events/leg-outbound",
      media_url: "wss://voice.example.test/twilio/media/token",
      answering_machine_detection: :detect
    }
  end

  defp form_fields(conn) do
    conn
    |> Req.Test.raw_body()
    |> URI.query_decoder()
    |> Enum.to_list()
  end

  defp field(fields, key), do: List.keyfind(fields, key, 0) |> elem(1)

  defp signature(parameters) do
    signed =
      parameters
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce(@url, fn {key, value}, input -> input <> key <> value end)

    :crypto.mac(:hmac, :sha, @auth_token, signed)
    |> Base.encode64()
  end

  defp verify_on_exit!(_context) do
    Req.Test.verify_on_exit!()
    :ok
  end
end
