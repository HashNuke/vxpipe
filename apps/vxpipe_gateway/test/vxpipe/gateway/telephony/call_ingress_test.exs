defmodule Vxpipe.Gateway.Telephony.CallIngressTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Event, Submission}

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    IncomingLegActivationResult,
    IngressIdentity,
    LegSupervisor,
    LegUsage,
    MediaBinding
  }

  alias Vxpipe.Gateway.TestTelephonyCallBackend

  @now ~U[2026-09-11 10:40:01.000000Z]

  setup do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})

    options = [
      backend: TestTelephonyCallBackend.backend(backend),
      clock: fn -> @now end,
      leg_supervisor: LegSupervisor
    ]

    on_exit(fn -> LegSupervisor.stop(:telnyx, "primary-phone", "call-leg-1") end)

    %{backend: backend, options: options}
  end

  test "claims and activates once, then projects the provider answer occurrence", context do
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())

    assert [
             {:claim_incoming, {:tenant, "AAAAAAAAAAAAAAAA"}, "primary-phone", "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:activate_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1", leg}
           ] = TestTelephonyCallBackend.operations(context.backend)

    answered = answered_event()
    assert :ok = CallIngress.handle_event(context.options, identity(), answered)
    assert :ok = CallIngress.handle_event(context.options, identity(), answered)

    assert [
             {:claim_incoming, {:tenant, "AAAAAAAAAAAAAAAA"}, "primary-phone", "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:activate_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1", ^leg},
             {:mark_incoming_started, "30000000-0000-4000-8000-000000000003", "rinc_phone-1",
              answered_at}
           ] = TestTelephonyCallBackend.operations(context.backend)

    assert answered_at == answered.occurred_at
  end

  test "routes later exact-leg events through memory without another durable claim", context do
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())

    answered = answered_event()
    assert :ok = CallIngress.handle_event(context.options, identity(), answered)

    dtmf = %{
      answered
      | kind: :dtmf,
        provider_event_id: "event-dtmf-1",
        digit: "1"
    }

    assert :ok = CallIngress.handle_event(context.options, identity(), dtmf)
    assert_receive {:test_live_telephony_event, ^dtmf, source}
    assert source == self()

    assert Enum.count(TestTelephonyCallBackend.operations(context.backend), fn
             {:claim_incoming, _scope, _service, _leg} -> true
             _operation -> false
           end) == 1

    mismatched = %{answered | provider_call_session_id: "call-session-other"}

    assert {:error, :telephony_leg_mismatch} =
             CallIngress.handle_event(context.options, identity(), mismatched)

    refute_receive {:test_live_telephony_event, ^mismatched, _source}
  end

  test "uses admitted media start as live evidence when it arrives before answered", context do
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())

    media_started = %{
      incoming_event()
      | kind: :media_started,
        provider_event_id: nil,
        occurred_at: nil,
        stream_id: "stream-1"
    }

    assert :ok = CallIngress.handle_event(context.options, identity(), media_started)

    assert [
             {:mark_incoming_started, "30000000-0000-4000-8000-000000000003", "rinc_phone-1",
              @now},
             {:handle_live_event, "30000000-0000-4000-8000-000000000003", :media_started, nil}
           ] = Enum.take(TestTelephonyCallBackend.operations(context.backend), -2)

    assert_receive {:test_live_telephony_event, ^media_started, source}
    assert source == self()
  end

  test "records one startup failure and does not restart the crashed call" do
    backend =
      start_supervised!(
        {TestTelephonyCallBackend, observer: self(), start_failure?: true},
        id: :telephony_start_failure_backend
      )

    options = [
      backend: TestTelephonyCallBackend.backend(backend),
      clock: fn -> @now end,
      leg_supervisor: LegSupervisor
    ]

    assert :ok = CallIngress.handle_event(options, identity(), incoming_event())
    assert :ok = CallIngress.handle_event(options, identity(), incoming_event())

    assert [
             {:claim_incoming, _first_scope, "primary-phone", "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:mark_incoming_failed, "30000000-0000-4000-8000-000000000003", :room_start_failed}
           ] = TestTelephonyCallBackend.operations(backend)
  end

  test "records a rejected carrier activation without marking the call started" do
    backend =
      start_supervised!(
        {TestTelephonyCallBackend, observer: self(), activation_failure?: true},
        id: :telephony_activation_failure_backend
      )

    options = [
      backend: TestTelephonyCallBackend.backend(backend),
      clock: fn -> @now end,
      leg_supervisor: LegSupervisor
    ]

    assert :ok = CallIngress.handle_event(options, identity(), incoming_event())

    assert [
             {:claim_incoming, _scope, "primary-phone", "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:activate_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1", leg},
             {:mark_incoming_failed, "30000000-0000-4000-8000-000000000003",
              :leg_activation_failed}
           ] = TestTelephonyCallBackend.operations(backend)

    assert is_pid(leg)
  end

  test "retains incoming carrier usage through answer and end callbacks", context do
    claim = TestTelephonyCallBackend.claim(context.backend)

    binding = %MediaBinding{
      provider: claim.provider,
      service_id: claim.service,
      ingress_key: "ingress_telnyx_primary",
      tenant_id: claim.call.tenant_key,
      call_id: claim.call.id,
      room_id: claim.call.room_id,
      incarnation_id: "rinc_phone-1",
      participant_id: claim.participant_id,
      provider_connection_id: claim.provider_connection_id,
      provider_call_control_id: claim.provider_call_control_id,
      provider_call_leg_id: claim.provider_call_leg_id,
      provider_call_session_id: claim.provider_call_session_id,
      client_state_leg_id: "tleg-incoming-usage",
      leg: self()
    }

    usage =
      LegUsage.start_incoming(binding,
        usage_clock: fn -> ~U[2026-09-12 06:00:00.000Z] end,
        usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
      )

    activation = %IncomingLegActivationResult{
      binding: binding,
      media_url: "wss://voice.example.test/media",
      submission: %Submission{
        status: :accepted,
        provider_call_control_id: claim.provider_call_control_id
      },
      usage: usage
    }

    :ok = TestTelephonyCallBackend.put_activation(context.backend, activation)
    assert_receive {:test_usage_observations, [started]}
    assert started.measurement.component == "carrier_legs"

    assert {:ok, "wss://voice.example.test/media"} =
             CallIngress.handle_event(context.options, identity(), incoming_event())

    answered = %{
      answered_event()
      | occurred_at: ~U[2026-09-12 06:00:03.250Z]
    }

    assert :ok = CallIngress.handle_event(context.options, identity(), answered)
    assert_receive {:test_usage_observations, [connected]}
    assert connected.delivery_id == answered.provider_event_id

    ended = %{
      answered
      | kind: :ended,
        provider_event_id: "event-ended-incoming-usage",
        occurred_at: ~U[2026-09-12 06:01:08.750Z],
        end_reason: :hangup
    }

    assert :ok = CallIngress.handle_event(context.options, identity(), ended)
    assert_receive {:test_usage_observations, [duration]}
    assert duration.outcome == :succeeded
    assert duration.measurement.component == "connection_duration"
    assert duration.measurement.quantity == 65_500
    assert duration.provider.operation_id == claim.provider_call_leg_id
    assert duration.provider.session_id == claim.provider_call_session_id
  end

  defp identity do
    %IngressIdentity{
      service_id: "primary-phone",
      ingress_key: "ingress_telnyx_primary",
      scope: {:tenant, "AAAAAAAAAAAAAAAA"},
      provider: :telnyx,
      provider_connection_id: "voice-application-1"
    }
  end

  defp incoming_event do
    %Event{
      kind: :incoming,
      provider: :telnyx,
      provider_event_id: "event-incoming-1",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      occurred_at: ~U[2026-09-11 10:39:59.000000Z],
      occurred_at_provenance: :provider_reported,
      from: "+15550001001",
      to: "+15550001000"
    }
  end

  defp answered_event do
    %{
      incoming_event()
      | kind: :answered,
        provider_event_id: "event-answered-1",
        occurred_at: ~U[2026-09-11 10:40:00.123456Z]
    }
  end
end
