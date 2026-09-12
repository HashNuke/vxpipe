defmodule Vxpipe.Gateway.Telephony.OutgoingLegTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{EndLeg, Event, LegReference, OutboundLegRequest}

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    ConfiguredService,
    LegSupervisor,
    MediaAdmission,
    OutgoingLeg,
    OutgoingLegConnector,
    OutgoingLegReference,
    ServiceRegistry
  }

  setup do
    media_admission = start_supervised!({MediaAdmission, name: nil})
    leg_id = "outgoing-#{System.unique_integer([:positive, :monotonic])}"

    on_exit(fn -> LegSupervisor.stop_outgoing(leg_id) end)

    %{leg_id: leg_id, media_admission: media_admission}
  end

  test "submits one dial and binds accepted provider identity to the exact leg", context do
    service = service(self(), answering_machine_detection: :detect)
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
    assert dial.answering_machine_detection == :detect

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

  test "submits the same outbound-leg contract through a configured Twilio service", context do
    service = twilio_service(self(), answering_machine_detection: :detect)
    request = %{request() | service_id: "twilio-primary"}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_twilio_dial, dial}

    assert dial.leg_id == context.leg_id
    assert dial.from == "+15550001000"
    assert dial.to == "+15550001001"
    assert dial.answering_machine_detection == :detect

    assert dial.callback_url ==
             "https://voice.example.test/voice/api/telephony/twilio/outbound_ingress/events/#{context.leg_id}"

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url)
    assert binding.provider == :twilio
    assert binding.leg == leg
    assert binding.provider_call_control_id == "CA00000000000000000000000000000001"
    assert binding.provider_call_leg_id == "CA00000000000000000000000000000001"
    assert binding.provider_call_session_id == nil
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

  test "adopts a signed outgoing event after an unknown submission", context do
    service = service(self(), api_key: "unknown:#{:erlang.pid_to_list(self())}")
    request = request()

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_telephony_dial, dial}

    mismatched = %{outgoing_event(context.leg_id) | to: "+15550001002"}

    assert {:error, :telephony_leg_mismatch} =
             CallIngress.handle_event([], service.identity, mismatched)

    event = outgoing_event(context.leg_id)
    assert :ok = CallIngress.handle_event([], service.identity, event)

    assert {:ok, ^leg} =
             LegSupervisor.lookup(:telnyx, "telnyx-primary", "outbound-call-leg")

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url)
    assert binding.leg == leg
    assert binding.provider_call_control_id == event.provider_call_control_id
    assert binding.provider_call_leg_id == event.provider_call_leg_id
    assert binding.provider_call_session_id == event.provider_call_session_id
  end

  test "adopts an out-of-order Twilio answered callback after an unknown submission", context do
    service =
      twilio_service(self(),
        auth_token: "unknown:#{:erlang.pid_to_list(self())}"
      )

    request = %{request() | service_id: "twilio-primary"}

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request,
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_twilio_dial, dial}

    event = twilio_answered_event(context.leg_id)
    assert :ok = CallIngress.handle_event([], service.identity, event)
    refute_receive {:test_twilio_dial, _duplicate}

    assert {:ok, ^leg} =
             LegSupervisor.lookup(:twilio, "twilio-primary", event.provider_call_leg_id)

    assert {:ok, binding} = consume_media(context.media_admission, dial.media_url)
    assert binding.leg == leg
    assert binding.provider_call_control_id == event.provider_call_control_id
    assert binding.provider_call_leg_id == event.provider_call_leg_id
    assert binding.provider_call_session_id == nil
  end

  test "the engine connector resolves the tenant service and starts one supervised leg",
       context do
    registry = ServiceRegistry.init!(enabled: true, services: [service_options(self())])

    connector = [
      leg_id: fn -> context.leg_id end,
      leg_supervisor: LegSupervisor,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    assert {:ok,
            %OutgoingLegReference{
              leg: leg,
              leg_id: leg_id,
              supervisor: LegSupervisor
            }} = OutgoingLegConnector.connect(connector, request(), 1_000)

    assert is_pid(leg)
    assert leg_id == context.leg_id
    assert_receive {:test_telephony_dial, %{leg_id: ^leg_id}}
    refute_receive {:test_telephony_dial, _duplicate}
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(leg_id)
  end

  test "configured machine detection ends the exact attempted leg once", context do
    service = service(self(), answering_machine_detection: :detect)
    leg = start_accepted_leg(context, service)
    monitor = Process.monitor(leg)

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:machine), 1_000)

    assert_receive {:test_telephony_end_leg,
                    %EndLeg{
                      leg: %LegReference{
                        leg_id: leg_id,
                        provider_call_control_id: "outbound-call-control"
                      },
                      reason: :answering_machine
                    }}

    assert leg_id == context.leg_id
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _duplicate}
  end

  test "human and unknown detection keep waiting for explicit acceptance", context do
    service = service(self(), answering_machine_detection: :detect)
    leg = start_accepted_leg(context, service)

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:human), 1_000)
    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:unknown), 1_000)
    refute_receive {:test_telephony_end_leg, _request}
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
  end

  test "disabled detection and mismatched lifecycle evidence cannot end the leg", context do
    leg = start_accepted_leg(context, service(self(), []))

    assert :ok = OutgoingLeg.dispatch(leg, answering_machine_event(:machine), 1_000)

    mismatched = %{
      ended_event(:failed)
      | provider_call_control_id: "another-call-control"
    }

    assert {:error, :telephony_leg_mismatch} = OutgoingLeg.dispatch(leg, mismatched, 1_000)
    refute_receive {:test_telephony_end_leg, _request}
    assert {:ok, ^leg} = LegSupervisor.lookup_outgoing(context.leg_id)
  end

  test "a carrier-ended event retires locally without a redundant hangup", context do
    leg = start_accepted_leg(context, service(self(), []))
    monitor = Process.monitor(leg)

    assert :ok = OutgoingLeg.dispatch(leg, ended_event(:busy), 1_000)

    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _request}
  end

  test "reports one carrier leg and its provider-timed connection duration", context do
    service = service(self(), [])
    started_at = ~U[2026-09-12 04:00:00.000Z]

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission,
               usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()},
               usage_clock: fn -> started_at end
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_usage_observations, [started]}
    assert_receive {:test_telephony_dial, _dial}
    assert_receive {:test_usage_observations, [identified]}

    assert started.measurement.component == "carrier_legs"
    assert started.measurement.quantity == 1
    assert started.attribution.leg_id == context.leg_id
    assert started.provider.operation_id == nil

    assert identified.provider.name == "telnyx"
    assert identified.provider.integration_id == "telnyx-primary"
    assert identified.provider.operation_id == "outbound-call-leg"
    assert identified.provider.session_id == "outbound-call-session"

    answered =
      lifecycle_event(:answered,
        provider_event_id: "event-answered-usage",
        occurred_at: ~U[2026-09-12 04:00:03.250Z]
      )

    assert :ok = OutgoingLeg.dispatch(leg, answered, 1_000)
    assert_receive {:test_usage_observations, [connected]}
    assert connected.measurement == nil
    assert connected.delivery_id == "event-answered-usage"

    assert :ok = OutgoingLeg.dispatch(leg, answered, 1_000)
    refute_receive {:test_usage_observations, _duplicate_connected}

    mismatched = %{
      ended_event(:hangup)
      | provider_event_id: "event-ended-mismatched-usage",
        provider_call_control_id: "another-call-control",
        occurred_at: ~U[2026-09-12 04:01:00.000Z]
    }

    assert {:error, :telephony_leg_mismatch} = OutgoingLeg.dispatch(leg, mismatched, 1_000)
    refute_receive {:test_usage_observations, _mismatched_usage}

    monitor = Process.monitor(leg)

    ended =
      lifecycle_event(:ended,
        provider_event_id: "event-ended-usage",
        occurred_at: ~U[2026-09-12 04:01:08.750Z],
        end_reason: :hangup
      )

    assert :ok = OutgoingLeg.dispatch(leg, ended, 1_000)
    assert_receive {:test_usage_observations, [duration]}
    assert duration.outcome == :succeeded
    assert duration.measurement.component == "connection_duration"
    assert duration.measurement.quantity == 65_500
    assert duration.measurement.provenance == :provider_reported
    assert duration.provider.operation_id == "outbound-call-leg"
    assert duration.delivery_id == "event-ended-usage"
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
  end

  test "retains a rejected carrier dial without inventing duration or provider identity",
       context do
    service = service(self(), api_key: "reject:#{:erlang.pid_to_list(self())}")

    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission,
               usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
             )

    assert {:error, :command_rejected} = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_usage_observations, [started]}
    assert_receive {:test_telephony_dial, _dial}
    assert_receive {:test_usage_observations, [failed]}

    assert started.measurement.component == "carrier_legs"
    assert failed.outcome == :failed
    assert failed.measurement == nil
    assert failed.provider.operation_id == nil
    assert failed.provider.session_id == nil
  end

  test "connector cleanup ends a known exact carrier leg before retiring it", context do
    registry = ServiceRegistry.init!(enabled: true, services: [service_options(self())])

    connector = [
      leg_id: fn -> context.leg_id end,
      leg_supervisor: LegSupervisor,
      media_admission: context.media_admission,
      service_registry: registry
    ]

    assert {:ok, %OutgoingLegReference{leg: leg} = reference} =
             OutgoingLegConnector.connect(connector, request(), 1_000)

    assert_receive {:test_telephony_dial, _dial}
    monitor = Process.monitor(leg)

    assert :ok = OutgoingLegConnector.disconnect(connector, reference)

    assert_receive {:test_telephony_end_leg,
                    %EndLeg{
                      leg: %LegReference{
                        leg_id: leg_id,
                        provider_call_control_id: "outbound-call-control"
                      },
                      reason: :transfer_cancelled
                    }}

    assert leg_id == context.leg_id
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}
    refute_receive {:test_telephony_end_leg, _duplicate}
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
      to: "+15550001001"
    }
  end

  defp service(observer, overrides) do
    assert {:ok, service} =
             ConfiguredService.new(service_options(observer, overrides))

    service
  end

  defp service_options(observer, overrides \\ []) do
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
  end

  defp twilio_service(observer, overrides) do
    options =
      Keyword.merge(
        [
          id: "twilio-primary",
          ingress_key: "outbound_ingress",
          scope: {:tenant, "tenantkey1234567"},
          provider: :twilio,
          account_sid: "AC00000000000000000000000000000000",
          auth_token: "observer:#{:erlang.pid_to_list(observer)}",
          outbound_number: "+15550001000",
          public_base_url: "https://voice.example.test/voice",
          adapter: Vxpipe.Gateway.TestTwilioTelephonyAdapter
        ],
        overrides
      )

    assert {:ok, service} = ConfiguredService.new(options)
    service
  end

  defp start_accepted_leg(context, service) do
    assert {:ok, leg} =
             LegSupervisor.start_outgoing(
               LegSupervisor,
               context.leg_id,
               request(),
               service,
               context.media_admission
             )

    assert :ok = OutgoingLeg.await(leg, 1_000)
    assert_receive {:test_telephony_dial, %{leg_id: leg_id}}
    assert leg_id == context.leg_id
    leg
  end

  defp answering_machine_event(result) do
    lifecycle_event(:answering_machine,
      answering_machine: result,
      provider_event_id: "event-amd-#{result}"
    )
  end

  defp ended_event(reason) do
    lifecycle_event(:ended, end_reason: reason, provider_event_id: "event-ended-#{reason}")
  end

  defp lifecycle_event(kind, overrides) do
    struct!(
      Event,
      Keyword.merge(
        [
          kind: kind,
          provider: :telnyx,
          provider_event_id: "event-lifecycle",
          provider_connection_id: "voice-application-1",
          provider_call_control_id: "outbound-call-control",
          provider_call_leg_id: "outbound-call-leg",
          provider_call_session_id: "outbound-call-session",
          occurred_at: ~U[2026-09-11 14:30:00Z],
          occurred_at_provenance: :provider_reported
        ],
        overrides
      )
    )
  end

  defp outgoing_event(leg_id) do
    %Event{
      kind: :outgoing,
      provider: :telnyx,
      provider_event_id: "event-outgoing",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "outbound-call-control",
      provider_call_leg_id: "outbound-call-leg",
      provider_call_session_id: "outbound-call-session",
      leg_id: leg_id,
      occurred_at: ~U[2026-09-11 13:45:00Z],
      occurred_at_provenance: :provider_reported,
      from: "+15550001000",
      to: "+15550001001"
    }
  end

  defp twilio_answered_event(leg_id) do
    %Event{
      kind: :answered,
      provider: :twilio,
      provider_event_id: "CA00000000000000000000000000000002:status:2",
      provider_connection_id: "AC00000000000000000000000000000000",
      provider_call_control_id: "CA00000000000000000000000000000002",
      provider_call_leg_id: "CA00000000000000000000000000000002",
      provider_call_session_id: nil,
      leg_id: leg_id,
      occurred_at: ~U[2026-09-11 13:46:00Z],
      occurred_at_provenance: :locally_measured,
      sequence_number: 2,
      from: "+15550001000",
      to: "+15550001001"
    }
  end

  defp consume_media(media_admission, media_url) do
    %URI{path: path} = URI.parse(media_url)
    [token | _rest] = path |> String.split("/", trim: true) |> Enum.reverse()
    MediaAdmission.consume(media_admission, "outbound_ingress", token)
  end
end
