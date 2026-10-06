defmodule Vxpipe.Gateway.Telephony.OutgoingLegReviewTest do
  @moduledoc """
  Reproduction from the 2026-10-06 outgoing-call review
  (docs/milestones/outgoing-call-review-fixes.md). It failed when written.
  """

  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.CallEngine.Telephony.{Event, OutboundLegRequest}
  alias Vxpipe.Gateway.Telephony.{ConfiguredService, LegSupervisor, MediaAdmission, OutgoingLeg}

  setup do
    media_admission = start_supervised!({MediaAdmission, name: nil})
    leg_id = "outgoing-review-#{System.unique_integer([:positive, :monotonic])}"
    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)
    %{leg_id: leg_id, media_admission: media_admission}
  end

  # Issue 6 (mechanism): OutgoingLeg submits the carrier dial inside handle_continue/2, so
  # a webhook for that leg (here call.answered) dispatched while the dial request is still
  # in flight blocks behind it. If the dial outlasts the dispatcher's call timeout (5 s in
  # CallIngress), the webhook is answered 503 and the answer never reaches the room.
  # Production then records `no_answer` for an answered call (observed live: Telnyx ->
  # Twilio failed 4 of 9 runs with 503s on outgoing-leg webhooks).
  test "an answer webhook arriving while the dial request is in flight is not lost", c do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}
    token = request.attempt_id

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               c.leg_id,
               request,
               service(api_key: "blocked:#{:erlang.pid_to_list(self())}"),
               c.media_admission
             )

    assert_receive {:test_telephony_dial_pending, adapter}, 1_000

    # The dispatcher gives up before the slow dial returns (scaled down from 5 s).
    dispatch = Task.async(fn -> OutgoingLeg.dispatch(leg, answered(), 200) end)
    result = Task.await(dispatch, 2_000)
    send(adapter, :release_test_telephony_dial)
    assert :ok = OutgoingLeg.await(leg, 1_000)

    assert result == :ok,
           "webhook rejected while the dial was in flight: #{inspect(result)}"

    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :answered}, 1_000
  end

  test "a Twilio answer callback binds media before the in-flight dial returns", c do
    account = "AC00000000000000000000000000000000"

    service =
      service(
        provider: :twilio,
        provider_connection_id: nil,
        public_key: nil,
        api_key: nil,
        account_sid: account,
        auth_token: "blocked:#{:erlang.pid_to_list(self())}",
        adapter: Vxpipe.Gateway.TestTwilioTelephonyAdapter
      )

    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               c.leg_id,
               request,
               service,
               c.media_admission
             )

    assert_receive {:test_twilio_dial, dial}, 1_000
    assert_receive {:test_twilio_dial_pending, adapter}, 1_000
    on_exit(fn -> send(adapter, :release_test_telephony_dial) end)

    parameters = %{
      "AccountSid" => account,
      "CallSid" => "CA00000000000000000000000000000001",
      "CallStatus" => "in-progress",
      "Direction" => "outbound-api",
      "From" => service.outbound_number,
      "To" => request.to,
      "SequenceNumber" => "1"
    }

    public_url = Vxpipe.Providers.Twilio.PublicEndpoint.event_url(service, c.leg_id)

    signed =
      Enum.reduce(Enum.sort(parameters), public_url, fn {key, value}, text ->
        text <> key <> value
      end)

    signature =
      :crypto.mac(:hmac, :sha, Keyword.fetch!(service.adapter_options, :auth_token), signed)
      |> Base.encode64()

    endpoint =
      Vxpipe.Gateway.TestTelephonyServiceRepository.endpoint(
        telephony: [
          enabled: true,
          handler: {Vxpipe.Gateway.Telephony.CallIngress, [timeout: 200]},
          services: [
            options(
              provider: :twilio,
              provider_connection_id: nil,
              public_key: nil,
              api_key: nil,
              account_sid: account,
              auth_token: "blocked:#{:erlang.pid_to_list(self())}",
              adapter: Vxpipe.Gateway.TestTwilioTelephonyAdapter
            )
          ]
        ]
      )

    response =
      conn(
        :post,
        "/api/telephony/twilio/#{service.identity.ingress_key}/events/#{c.leg_id}",
        URI.encode_query(parameters)
      )
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("x-twilio-signature", signature)
      |> Vxpipe.Gateway.HTTP.Endpoint.call(endpoint)

    assert response.status == 200
    token = request.attempt_id
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :answered}, 1_000
    uri = URI.parse(dial.media_url)
    token = uri.path |> String.split("/") |> List.last()

    assert {:ok, binding} =
             MediaAdmission.consume(
               c.media_admission,
               service.identity.ingress_key,
               token,
               service
             )

    assert binding.leg == leg
    send(adapter, :release_test_telephony_dial)
    assert :ok = OutgoingLeg.await(leg, 1_000)
  end

  test "foreign early identities have no room effects and buffered events are bounded", c do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               c.leg_id,
               request,
               service(api_key: "blocked:#{:erlang.pid_to_list(self())}"),
               c.media_admission
             )

    assert_receive {:test_telephony_dial_pending, adapter}, 1_000
    on_exit(fn -> send(adapter, :release_test_telephony_dial) end)

    assert {:error, :telephony_leg_mismatch} =
             OutgoingLeg.dispatch(leg, %{answered() | leg_id: "foreign"}, 200)

    assert {:error, :telephony_leg_mismatch} =
             OutgoingLeg.dispatch(leg, %{answered() | provider_connection_id: "foreign"}, 200)

    event = %{answered() | provider_call_control_id: "different-call"}
    for _ <- 1..40, do: assert(:ok == OutgoingLeg.dispatch(leg, event, 200))

    for i <- 1..31,
        do:
          assert(
            :ok == OutgoingLeg.dispatch(leg, %{event | provider_event_id: "other-#{i}"}, 200)
          )

    assert {:error, :telephony_event_buffer_full} =
             OutgoingLeg.dispatch(leg, %{event | provider_event_id: "overflow"}, 200)

    send(adapter, :release_test_telephony_dial)
    assert :ok = OutgoingLeg.await(leg, 1_000)
    _ = :sys.get_state(leg)
    refute_received {:vxpipe_outbound_leg, _, _, :answered}
    assert :ok = OutgoingLeg.dispatch(leg, answered(), 200)
    token = request.attempt_id
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :answered}, 1_000
  end

  test "stopping a leg cancels its blocked supervised HTTP worker", c do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               c.leg_id,
               request(),
               service(api_key: "blocked:#{:erlang.pid_to_list(self())}"),
               c.media_admission
             )

    assert_receive {:test_telephony_dial_pending, adapter}, 1_000
    monitor = Process.monitor(adapter)
    leg_monitor = Process.monitor(leg)
    assert :ok = LegSupervisor.stop_outgoing(c.leg_id)
    assert_receive {:DOWN, ^leg_monitor, :process, ^leg, _reason}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^adapter, _reason}, 1_000
    refute_received {:test_telephony_end_leg, _}
  end

  test "a buffered answer survives an unknown REST result and later full identity", c do
    request = %{request() | purpose: :initial, room_owner: self(), attempt_id: make_ref()}
    service = service(api_key: "blocked:#{:erlang.pid_to_list(self())}")

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               c.leg_id,
               request,
               service,
               c.media_admission
             )

    assert_receive {:test_telephony_dial_pending, adapter}, 1_000
    on_exit(fn -> send(adapter, :release_test_telephony_dial) end)
    assert :ok = OutgoingLeg.dispatch(leg, answered(), 200)
    send(adapter, :release_test_telephony_dial_unknown)
    assert {:ok, :unknown} = OutgoingLeg.await(leg, 1_000)
    refute_received {:vxpipe_outbound_leg, _, _, :answered}

    event = %{
      answered()
      | kind: :outgoing,
        leg_id: c.leg_id,
        from: service.outbound_number,
        to: request.to
    }

    assert :ok = OutgoingLeg.dispatch(leg, event, 200)
    token = request.attempt_id
    assert_receive {:vxpipe_outbound_leg, ^token, ^leg, :answered}, 1_000
  end

  defp answered do
    %Event{
      kind: :answered,
      provider: :telnyx,
      provider_event_id: "event-answered",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "outbound-call-control",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      occurred_at: ~U[2026-10-06 10:00:00Z],
      occurred_at_provenance: :provider_reported
    }
  end

  defp request do
    %OutboundLegRequest{
      tenant_id: "tenantkey1234567",
      actor_id: "actor-outbound",
      call_id: "call-outbound",
      room_id: "room-outbound",
      incarnation_id: "rinc-outbound",
      participant_id: "participant-support",
      service_id: "telnyx-primary",
      service_reference: Vxpipe.Gateway.TestTelephonyServiceRepository.reference(options([])),
      to: "+15550001001"
    }
  end

  defp service(overrides) do
    assert {:ok, service} = ConfiguredService.new(options(overrides))

    %{
      service
      | identity: %{
          service.identity
          | service_reference:
              Vxpipe.Gateway.TestTelephonyServiceRepository.reference(options(overrides))
        }
    }
  end

  defp options(overrides) do
    Keyword.merge(
      [
        id: "telnyx-primary",
        ingress_key: "outbound_ingress",
        scope: {:tenant, "tenantkey1234567"},
        provider: :telnyx,
        provider_connection_id: "voice-application-1",
        public_key: Base.encode64(:binary.copy(<<1>>, 32)),
        api_key: "observer:#{:erlang.pid_to_list(self())}",
        outbound_number: "+15550001000",
        public_base_url: "https://voice.example.test/voice",
        adapter: Vxpipe.Gateway.TestTelephonyAdapter
      ],
      overrides
    )
  end
end
