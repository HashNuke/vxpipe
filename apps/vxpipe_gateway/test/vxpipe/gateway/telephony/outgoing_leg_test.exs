defmodule Vxpipe.Gateway.Telephony.OutgoingLegTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.OutboundLegRequest

  alias Vxpipe.Gateway.Telephony.{
    ConfiguredService,
    LegSupervisor,
    MediaAdmission,
    OutgoingLeg
  }

  setup do
    media_admission = start_supervised!({MediaAdmission, name: nil})
    leg_id = "outgoing-#{System.unique_integer([:positive, :monotonic])}"

    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    %{leg_id: leg_id, media_admission: media_admission}
  end

  test "submits one dial and binds accepted provider identity to the exact leg", context do
    service = service(self())
    request = request()

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert {:ok, ^leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)

    assert_receive {:test_telephony_dial, dial}
    refute_receive {:test_telephony_dial, _duplicate}

    assert dial.leg_id == context.leg_id
    assert dial.from == "+15550001000"
    assert dial.to == "+15550001001"

    assert dial.callback_url ==
             "https://voice.example.test/voice/api/telephony/telnyx/outbound_ingress/events"

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url)
    assert binding.leg == leg
    assert binding.client_state_leg_id == context.leg_id
    assert binding.tenant_id == request.tenant_id
    assert binding.call_id == request.call_id
    assert binding.room_id == request.room_id
    assert binding.incarnation_id == request.incarnation_id
    assert binding.participant_id == request.participant_id
    assert binding.provider_call_control_id == "outbound-call-control"
    assert binding.provider_call_leg_id == "outbound-call-leg"
    assert binding.provider_call_session_id == "outbound-call-session"
  end

  test "rejects an inbound-only service before submitting a dial", context do
    service = service(self(), outbound_number: nil)

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission
             )

    assert {:error, :invalid_outbound_telephony_request} = OutgoingLeg.await(leg, 1_000)
    refute_receive {:test_telephony_dial, _request}
  end

  defp request do
    %OutboundLegRequest{
      tenant_id: "tenantkey1234567",
      call_id: "call-outbound",
      room_id: "room-outbound",
      incarnation_id: "rinc-outbound",
      participant_id: "participant-support",
      service_id: "telnyx-primary",
      to: "+15550001001",
      answering_machine_detection: :detect
    }
  end

  defp service(observer, overrides \\ []) do
    assert {:ok, service} =
             ConfiguredService.new(
               Keyword.merge(
                 [
                   id: "telnyx-primary",
                   ingress_key: "outbound_ingress",
                   scope: {:tenant, "tenantkey1234567"},
                   provider: :telnyx,
                   provider_connection_id: "voice-application-1",
                   public_key: Base.encode64(:binary.copy(<<1>>, 32)),
                   api_key: "observer:#{:erlang.pid_to_list(observer)}",
                   outbound_number: "+15550001000",
                   public_base_url: "https://voice.example.test/voice",
                   adapter: Vxpipe.Gateway.TestTelephonyAdapter
                 ],
                 overrides
               )
             )

    service
  end

  defp consume_media(media_admission, media_url) do
    %URI{path: path} = URI.parse(media_url)
    [token | _rest] = path |> String.split("/", trim: true) |> Enum.reverse()
    MediaAdmission.consume(media_admission, "outbound_ingress", token)
  end
end
