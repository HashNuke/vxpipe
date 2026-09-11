defmodule Vxpipe.Gateway.Telephony.CallIngressTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.{CallIngress, IngressIdentity, LegSupervisor}
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

  test "claims, starts, and projects an incoming leg exactly once", context do
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())

    assert [
             {:claim_incoming, {:tenant, "AAAAAAAAAAAAAAAA"}, "primary-phone", "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:mark_incoming_started, "30000000-0000-4000-8000-000000000003", "rinc_phone-1",
              @now}
           ] = TestTelephonyCallBackend.operations(context.backend)
  end

  test "routes later exact-leg events through memory without another durable claim", context do
    assert :ok = CallIngress.handle_event(context.options, identity(), incoming_event())

    answered = %{incoming_event() | kind: :answered, provider_event_id: "event-answered-1"}
    assert :ok = CallIngress.handle_event(context.options, identity(), answered)
    assert_receive {:test_live_telephony_event, ^answered}

    assert Enum.count(TestTelephonyCallBackend.operations(context.backend), fn
             {:claim_incoming, _scope, _service, _leg} -> true
             _operation -> false
           end) == 1

    mismatched = %{answered | provider_call_session_id: "call-session-other"}

    assert {:error, :telephony_leg_mismatch} =
             CallIngress.handle_event(context.options, identity(), mismatched)

    refute_receive {:test_live_telephony_event, ^mismatched}
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
      from: "+15550001001",
      to: "+15550001000"
    }
  end
end
