defmodule Vxpipe.CallEngine.Telephony.AdapterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.InvalidTelephonyAdapter
  alias Vxpipe.CallEngine.Media.MixedFrame

  alias Vxpipe.CallEngine.Telephony.{
    Adapter,
    Answer,
    Dial,
    EndLeg,
    Event,
    LegReference,
    MediaPacket,
    SendMedia,
    Submission,
    Webhook
  }

  alias Vxpipe.CallEngine.TestTelephonyAdapter

  test "submits dial, answer, media, and end commands through one adapter contract" do
    config = %{
      observer: self(),
      signature: "valid",
      outcomes: %{dial: :unknown, answer: :accepted, send_media: :ok, end_leg: :accepted}
    }

    dial = %Dial{
      leg_id: "leg-outbound",
      from: "+15550001000",
      to: "+15550001001",
      callback_url: "https://voice.example.test/telnyx/events",
      media_url: "wss://voice.example.test/telnyx/media/token",
      answering_machine_detection: :detect
    }

    assert {:ok, %Submission{status: :unknown, provider_call_control_id: nil}} =
             Adapter.dial(TestTelephonyAdapter, config, dial)

    assert_receive {:fake_telephony, :dial, ^dial}

    reference = %LegReference{
      leg_id: "leg-outbound",
      provider_call_control_id: "provider-call-control"
    }

    answer = %Answer{
      leg: reference,
      media_url: "wss://voice.example.test/telnyx/media/token"
    }

    assert {:ok,
            %Submission{status: :accepted, provider_call_control_id: "provider-call-control"}} =
             Adapter.answer(TestTelephonyAdapter, config, answer)

    assert_receive {:fake_telephony, :answer, ^answer}

    media = %SendMedia{leg: reference, frame: mixed_frame()}
    assert :ok = Adapter.send_media(TestTelephonyAdapter, config, media)
    assert_receive {:fake_telephony, :send_media, ^media}

    ending = %EndLeg{leg: reference, reason: :transfer_failed}

    assert {:ok, %Submission{status: :accepted}} =
             Adapter.end_leg(TestTelephonyAdapter, config, ending)

    assert_receive {:fake_telephony, :end_leg, ^ending}
  end

  test "verifies raw webhook bytes before decoding a provider-neutral event" do
    config = %{observer: self(), signature: "valid"}
    event = event(:incoming, from: "+15550001001", to: "+15550001000")

    valid = %Webhook{
      headers: %{"fake-signature" => "valid"},
      body: :erlang.term_to_binary(event),
      received_at: 1_789_120_000
    }

    assert {:ok, ^event} = Adapter.ingest_webhook(TestTelephonyAdapter, config, valid)
    assert_receive {:fake_telephony, :verify_webhook, ^valid}
    assert_receive {:fake_telephony, :decode_webhook, ^valid}

    invalid = %{valid | headers: %{"fake-signature" => "wrong"}}

    assert {:error, :invalid_signature} =
             Adapter.ingest_webhook(TestTelephonyAdapter, config, invalid)

    assert_receive {:fake_telephony, :verify_webhook, ^invalid}
    refute_receive {:fake_telephony, :decode_webhook, ^invalid}
  end

  test "accepts the complete provider-neutral fake event vocabulary" do
    packet = %MediaPacket{
      codec: :pcmu,
      sample_rate: 8_000,
      channels: 1,
      sequence_number: 12,
      timestamp: 960,
      payload: <<1, 2, 3>>
    }

    events = [
      event(:incoming, from: "+15550001001", to: "+15550001000"),
      event(:answered),
      event(:media_started, stream_id: "stream-1"),
      event(:media, stream_id: "stream-1", media: packet, sequence_number: 12),
      event(:dtmf, digit: "1"),
      event(:answering_machine, answering_machine: :unknown),
      event(:answering_machine, answering_machine: :human),
      event(:answering_machine, answering_machine: :machine),
      event(:ended, end_reason: :busy)
    ]

    config = %{observer: self(), signature: "valid"}

    for event <- events do
      message = :erlang.term_to_binary(event)
      assert {:ok, ^event} = Adapter.decode_media_message(TestTelephonyAdapter, config, message)
      assert_receive {:fake_telephony, :decode_media_message, ^message}
    end
  end

  test "acknowledges an authenticated provider event that the platform does not consume" do
    config = %{observer: self(), signature: "valid"}

    webhook = %Webhook{
      headers: %{"fake-signature" => "valid"},
      body: "ignored-provider-event",
      received_at: 1_789_120_000
    }

    assert :ignore = Adapter.ingest_webhook(TestTelephonyAdapter, config, webhook)
    assert_receive {:fake_telephony, :verify_webhook, ^webhook}
    assert_receive {:fake_telephony, :decode_webhook, ^webhook}
  end

  test "rejects malformed adapter output before it reaches room control" do
    dial = %Dial{
      leg_id: "leg-outbound",
      from: "+15550001000",
      to: "+15550001001",
      callback_url: "https://voice.example.test/telnyx/events",
      media_url: "wss://voice.example.test/telnyx/media/token",
      answering_machine_detection: :disabled
    }

    assert {:error, :invalid_adapter_response} =
             Adapter.dial(InvalidTelephonyAdapter, %{}, dial)
  end

  defp event(kind, attributes \\ []) do
    struct!(
      Event,
      Keyword.merge(
        [
          kind: kind,
          provider: :fake,
          provider_event_id: "provider-event-#{kind}",
          provider_call_control_id: "provider-call-control",
          provider_call_leg_id: "provider-call-leg",
          provider_call_session_id: "provider-call-session"
        ],
        attributes
      )
    )
  end

  defp mixed_frame do
    %MixedFrame{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      subscription_id: "subscription-test",
      recipient_participant_id: "participant-test",
      mode: :mix_minus,
      source_participant_ids: ["source-test"],
      timestamp: 960,
      policy_revision: 1,
      sample_rate: 48_000,
      channels: 1,
      payload: <<0, 0>>
    }
  end
end
