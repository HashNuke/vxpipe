defmodule Vxpipe.Gateway.Telephony.Telnyx.WebhookDecoderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Gateway.Telephony.Telnyx.WebhookDecoder

  @occurred_at ~U[2026-09-11 09:45:12.123456Z]

  test "normalizes an incoming call with its routing and correlation identity" do
    webhook = webhook("call.initiated", %{"direction" => "incoming"})

    assert {:ok,
            %Event{
              kind: :incoming,
              provider: :telnyx,
              provider_event_id: "event-1",
              provider_connection_id: "voice-application-1",
              provider_call_control_id: "call-control-1",
              provider_call_leg_id: "call-leg-1",
              provider_call_session_id: "call-session-1",
              occurred_at: @occurred_at,
              from: "+15550001001",
              to: "+15550001000"
            }} = WebhookDecoder.decode(webhook)
  end

  test "normalizes answered, DTMF, and standard or premium AMD events" do
    assert {:ok, %Event{kind: :answered}} =
             "call.answered" |> webhook() |> WebhookDecoder.decode()

    assert {:ok, %Event{kind: :dtmf, digit: "1"}} =
             "call.dtmf.received" |> webhook(%{"digit" => "1"}) |> WebhookDecoder.decode()

    amd_cases = [
      {"call.machine.detection.ended", "human", :human},
      {"call.machine.detection.ended", "machine", :machine},
      {"call.machine.detection.ended", "not_sure", :unknown},
      {"call.machine.premium.detection.ended", "human_residence", :human},
      {"call.machine.premium.detection.ended", "human_business", :human},
      {"call.machine.premium.detection.ended", "machine", :machine},
      {"call.machine.premium.detection.ended", "silence", :machine},
      {"call.machine.premium.detection.ended", "fax_detected", :machine},
      {"call.machine.premium.detection.ended", "not_sure", :unknown}
    ]

    Enum.each(amd_cases, fn {event_type, result, expected} ->
      assert {:ok, %Event{kind: :answering_machine, answering_machine: ^expected}} =
               event_type |> webhook(%{"result" => result}) |> WebhookDecoder.decode()
    end)
  end

  test "normalizes bounded hangup causes without retaining provider strings" do
    cases = [
      {"normal_clearing", :hangup},
      {"originator_cancel", :hangup},
      {"user_busy", :busy},
      {"no_answer", :no_answer},
      {"timeout", :timeout},
      {"call_rejected", :failed},
      {"provider_specific_failure", :failed}
    ]

    Enum.each(cases, fn {cause, expected} ->
      assert {:ok, %Event{kind: :ended, end_reason: ^expected}} =
               "call.hangup"
               |> webhook(%{"hangup_cause" => cause})
               |> WebhookDecoder.decode()
    end)
  end

  test "ignores authenticated events outside the consumed vocabulary" do
    ignored = [
      webhook("call.initiated", %{"direction" => "outgoing"}),
      webhook("streaming.started"),
      webhook("call.playback.ended"),
      webhook("future.provider.event")
    ]

    Enum.each(ignored, fn webhook ->
      assert :ignore = WebhookDecoder.decode(webhook)
    end)
  end

  test "rejects malformed envelopes and incomplete consumed events" do
    malformed = [
      raw_webhook("not-json"),
      raw_webhook(JSON.encode!(%{})),
      raw_webhook(JSON.encode!(%{"data" => %{"record_type" => "command"}})),
      webhook("call.answered", %{"call_leg_id" => nil}),
      webhook("call.answered", %{}, %{"occurred_at" => "not-a-date"}),
      webhook("call.dtmf.received", %{"digit" => "12"}),
      webhook("call.machine.detection.ended", %{"result" => "maybe"}),
      webhook("call.hangup", %{})
    ]

    Enum.each(malformed, fn webhook ->
      assert {:error, :invalid_telnyx_webhook} = WebhookDecoder.decode(webhook)
    end)
  end

  defp webhook(event_type, payload_overrides \\ %{}, data_overrides \\ %{}) do
    payload =
      Map.merge(
        %{
          "call_control_id" => "call-control-1",
          "call_leg_id" => "call-leg-1",
          "call_session_id" => "call-session-1",
          "connection_id" => "voice-application-1",
          "from" => "+15550001001",
          "to" => "+15550001000"
        },
        payload_overrides
      )

    data =
      Map.merge(
        %{
          "record_type" => "event",
          "event_type" => event_type,
          "id" => "event-1",
          "occurred_at" => DateTime.to_iso8601(@occurred_at),
          "payload" => payload
        },
        data_overrides
      )

    raw_webhook(JSON.encode!(%{"data" => data, "meta" => %{"attempt" => 1}}))
  end

  defp raw_webhook(body) do
    %Webhook{headers: %{}, body: body, received_at: 1_789_120_000}
  end
end
