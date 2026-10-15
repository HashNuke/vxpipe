defmodule Vxpipe.Gateway.Telephony.CallIngressTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.{Event, Submission}

  alias Vxpipe.Gateway.Telephony.{
    CallIngress,
    IncomingLegActivationResult,
    ConfiguredService,
    LegSupervisor,
    LegUsage,
    MediaBinding
  }

  alias Vxpipe.Gateway.TestTelephonyCallBackend

  @now ~U[2026-09-11 10:40:01.000000Z]

  setup do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})
    service = identity()

    options = [
      backend: TestTelephonyCallBackend.backend(backend),
      clock: fn -> @now end,
      leg_supervisor: LegSupervisor
    ]

    on_exit(fn -> LegSupervisor.stop(service.identity, "call-leg-1") end)

    %{backend: backend, options: options, service: service, test_observer: self()}
  end

  test "cancellation and binding errors cancel the owned gate before preparing an answer",
       context do
    for decision <- [:cancel, :error] do
      backend =
        start_supervised!({TestTelephonyCallBackend, observer: self(), bind_decision: decision},
          id: decision
        )

      options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
      assert :ok = handle_event(options, context.service, incoming_event())
      operations = TestTelephonyCallBackend.operations(backend)
      assert Enum.any?(operations, &match?({:bind_incoming, _, _}, &1))
      assert Enum.any?(operations, &match?({:cancel_incoming, _, _, _}, &1))
      refute Enum.any?(operations, &match?({:activate_incoming, _, _, _}, &1))
      refute Enum.any?(operations, &match?({:mark_incoming_failed, _, _}, &1))
      assert_receive {:incoming_end_requested, "call-control-1", _reason}
      LegSupervisor.stop(context.service.identity, "call-leg-1")
    end
  end

  test "answer callbacks remain responsive while carrier submission is blocked", context do
    backend =
      start_supervised!({TestTelephonyCallBackend, observer: self(), activation_blocked?: true},
        id: :blocked
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))

    _caller =
      start_supervised!(
        {Task,
         fn ->
           send(
             context.test_observer,
             {:incoming_result, handle_event(options, context.service, incoming_event())}
           )
         end}
      )

    assert_receive {:incoming_answer_pending, worker}
    on_exit(fn -> send(worker, :release_incoming_answer) end)
    assert {:ok, leg} = LegSupervisor.lookup(context.service.identity, "call-leg-1")
    assert :ok = Vxpipe.Gateway.Telephony.Leg.dispatch(leg, answered_event(), 200)

    assert Enum.any?(
             TestTelephonyCallBackend.operations(backend),
             &match?({:release_incoming, _, _}, &1)
           )

    send(worker, :release_incoming_answer)
    assert_receive {:incoming_result, :ok}
  end

  test "a failed start projection cancels admission without releasing startup", context do
    backend =
      start_supervised!({TestTelephonyCallBackend, observer: self(), started_failure?: true},
        id: :projection
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert :ok = handle_event(options, context.service, incoming_event())
    assert {:error, :call_unavailable} = handle_event(options, context.service, answered_event())
    operations = TestTelephonyCallBackend.operations(backend)
    assert Enum.any?(operations, &match?({:cancel_incoming, _, _, :call_unavailable}, &1))
    refute Enum.any?(operations, &match?({:release_incoming, _, _}, &1))
    assert_receive {:incoming_end_requested, "call-control-1", :call_unavailable}
  end

  test "late authenticated answer queues another end without releasing cancelled startup",
       context do
    backend =
      start_supervised!(
        {TestTelephonyCallBackend, observer: self(), started_failure?: true, end_blocked?: true},
        id: :late_answer
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert :ok = handle_event(options, context.service, incoming_event())
    assert {:error, :call_unavailable} = handle_event(options, context.service, answered_event())
    assert_receive {:incoming_end_pending, first_end}
    on_exit(fn -> send(first_end, :release_incoming_end) end)
    assert :ok = handle_event(options, context.service, answered_event())
    send(first_end, :release_incoming_end)
    assert_receive {:incoming_end_pending, retry_end}
    on_exit(fn -> send(retry_end, :release_incoming_end) end)

    refute Enum.any?(
             TestTelephonyCallBackend.operations(backend),
             &match?({:release_incoming, _, _}, &1)
           )

    send(retry_end, :release_incoming_end)
    refute_receive {:incoming_end_pending, _}
  end

  test "authenticated end retries local teardown after an unavailable backend", context do
    backend =
      start_supervised!({TestTelephonyCallBackend, observer: self(), end_event_failure?: true},
        id: :ended_retry
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert :ok = handle_event(options, context.service, incoming_event())
    assert :ok = handle_event(options, context.service, answered_event())
    ended = %{answered_event() | kind: :ended, end_reason: :hangup}
    assert {:error, :room_unavailable} = handle_event(options, context.service, ended)
    assert :ok = handle_event(options, context.service, ended)

    assert Enum.count(
             TestTelephonyCallBackend.operations(backend),
             &match?({:handle_live_event, _, :ended, _}, &1)
           ) == 2

    refute_receive {:incoming_end_requested, _, _}
  end

  test "authenticated end retries cancellation when answer preparation never happened", context do
    backend =
      start_supervised!(
        {TestTelephonyCallBackend, observer: self(), bind_decision: :cancel, cancel_failures: 2},
        id: :unprepared_end_retry
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert :ok = handle_event(options, context.service, incoming_event())
    ended = %{answered_event() | kind: :ended, end_reason: :hangup}
    assert {:error, :room_unavailable} = handle_event(options, context.service, ended)
    assert :ok = handle_event(options, context.service, ended)

    assert Enum.count(
             TestTelephonyCallBackend.operations(backend),
             &match?({:cancel_incoming, _, _, _}, &1)
           ) == 3
  end

  test "an observed room shutdown completes an unprepared carrier end without cancelling a missing runtime",
       context do
    room = start_supervised!({Agent, fn -> :room end}, id: :gated_room)

    backend =
      start_supervised!(
        {TestTelephonyCallBackend,
         observer: self(), bind_decision: :cancel, cancel_failures: 10, room_owner: room},
        id: :closed_unprepared
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert :ok = handle_event(options, context.service, incoming_event())
    assert {:ok, leg} = LegSupervisor.lookup(context.service.identity, "call-leg-1")
    monitor = Process.monitor(leg)
    stop_supervised!(:gated_room)
    assert_receive {:incoming_room_cancel_requested, :room_ended}
    ended = %{answered_event() | kind: :ended, end_reason: :hangup}
    assert :ok = handle_event(options, context.service, ended)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}

    assert Enum.count(
             TestTelephonyCallBackend.operations(backend),
             &match?({:cancel_incoming, _, _, _}, &1)
           ) == 2
  end

  test "a replay with no newly owned effects retires without starting or ending the carrier",
       context do
    backend =
      start_supervised!({TestTelephonyCallBackend, observer: self(), claimed?: true}, id: :replay)

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert :ok = handle_event(options, context.service, incoming_event())
    assert {:ok, replay} = LegSupervisor.lookup(context.service.identity, "call-leg-1")
    monitor = Process.monitor(replay)
    assert_receive {:DOWN, ^monitor, :process, ^replay, :normal}, 2_000

    refute Enum.any?(
             TestTelephonyCallBackend.operations(backend),
             &match?({:start_incoming, _}, &1)
           )

    refute_receive {:incoming_end_requested, _, _}
  end

  test "claims and activates once, then projects the provider answer occurrence", context do
    assert :ok = handle_event(context.options, context.service, incoming_event())
    assert :ok = handle_event(context.options, context.service, incoming_event())

    service_name = context.service.identity.service_id

    assert [
             {:claim_incoming, {:tenant, "AAAAAAAAAAAAAAAA"}, ^service_name, "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:bind_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1"},
             {:activate_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1", leg}
           ] = TestTelephonyCallBackend.operations(context.backend)

    answered = answered_event()
    assert :ok = handle_event(context.options, context.service, answered)
    assert :ok = handle_event(context.options, context.service, answered)

    assert [
             {:claim_incoming, {:tenant, "AAAAAAAAAAAAAAAA"}, ^service_name, "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:bind_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1"},
             {:activate_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1", ^leg},
             {:mark_incoming_started, "30000000-0000-4000-8000-000000000003", "rinc_phone-1",
              answered_at},
             {:release_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1"}
           ] = TestTelephonyCallBackend.operations(context.backend)

    assert answered_at == answered.occurred_at
  end

  test "routes later exact-leg events through memory without another durable claim", context do
    assert :ok = handle_event(context.options, context.service, incoming_event())

    answered = answered_event()
    assert :ok = handle_event(context.options, context.service, answered)

    dtmf = %{
      answered
      | kind: :dtmf,
        provider_event_id: "event-dtmf-1",
        digit: "1"
    }

    assert :ok = handle_event(context.options, context.service, dtmf)
    assert_receive {:test_live_telephony_event, ^dtmf, source}
    assert source == self()

    assert Enum.count(TestTelephonyCallBackend.operations(context.backend), fn
             {:claim_incoming, _scope, _service, _leg} -> true
             _operation -> false
           end) == 1

    mismatched = %{answered | provider_call_session_id: "call-session-other"}

    assert {:error, :telephony_leg_mismatch} =
             handle_event(context.options, context.service, mismatched)

    refute_receive {:test_live_telephony_event, ^mismatched, _source}
  end

  test "a scoped incoming owner remains discoverable without storage and duplicate admission",
       context do
    original = context.service

    reference = %{
      original.identity.service_reference
      | credential_owner: :platform,
        credential_name: "telnyx"
    }

    service = %{original | identity: %{original.identity | service_reference: reference}}
    on_exit(fn -> LegSupervisor.stop(service.identity, "call-leg-1") end)
    assert :ok = handle_event(context.options, service, incoming_event())

    body =
      JSON.encode!(%{
        data: %{payload: %{connection_id: "voice-application-1", call_leg_id: "call-leg-1"}}
      })

    assert {:ok, ^service, {:incoming, leg} = owner} =
             Vxpipe.Gateway.Telephony.WebhookService.scoped_telnyx_owner(:platform, body)

    assert :ok = CallIngress.handle_event(context.options, service, incoming_event(), owner)
    assert {:ok, ^leg} = LegSupervisor.lookup(service.identity, "call-leg-1")

    assert Enum.count(TestTelephonyCallBackend.operations(context.backend), fn
             {:claim_incoming, _, _, _} -> true
             _operation -> false
           end) == 1
  end

  test "uses admitted media start as live evidence when it arrives before answered", context do
    assert :ok = handle_event(context.options, context.service, incoming_event())

    media_started = %{
      incoming_event()
      | kind: :media_started,
        provider_event_id: nil,
        occurred_at: nil,
        stream_id: "stream-1"
    }

    assert :ok = handle_event(context.options, context.service, media_started)

    assert [
             {:mark_incoming_started, "30000000-0000-4000-8000-000000000003", "rinc_phone-1",
              @now},
             {:release_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1"},
             {:handle_live_event, "30000000-0000-4000-8000-000000000003", :media_started, nil}
           ] = Enum.take(TestTelephonyCallBackend.operations(context.backend), -3)

    assert_receive {:test_live_telephony_event, ^media_started, source}
    assert source == self()
  end

  test "records one startup failure and does not restart the crashed call", context do
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

    assert :ok = handle_event(options, context.service, incoming_event())
    assert :ok = handle_event(options, context.service, incoming_event())
    service_name = context.service.identity.service_id

    assert [
             {:claim_incoming, _first_scope, ^service_name, "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:mark_incoming_failed, "30000000-0000-4000-8000-000000000003", :room_start_failed}
           ] = TestTelephonyCallBackend.operations(backend)
  end

  test "records a rejected carrier activation without marking the call started", context do
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

    assert :ok = handle_event(options, context.service, incoming_event())
    service_name = context.service.identity.service_id

    assert [
             {:claim_incoming, _scope, ^service_name, "call-leg-1"},
             {:start_incoming, "30000000-0000-4000-8000-000000000003"},
             {:bind_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1"},
             {:activate_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1", leg},
             {:cancel_incoming, "30000000-0000-4000-8000-000000000003", "rinc_phone-1",
              :answer_submission_failed}
           ] = TestTelephonyCallBackend.operations(backend)

    assert is_pid(leg)
  end

  test "retains incoming carrier usage through answer and end callbacks", context do
    claim = TestTelephonyCallBackend.claim(context.backend)

    binding = %MediaBinding{
      provider: claim.provider,
      service_id: claim.service,
      ingress_key: context.service.identity.ingress_key,
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

    backend =
      start_supervised!(
        {TestTelephonyCallBackend,
         observer: self(), activation: activation, activation_blocked?: true},
        id: :usage_backend
      )

    options = Keyword.put(context.options, :backend, TestTelephonyCallBackend.backend(backend))
    assert_receive {:test_usage_observations, [started]}
    assert started.measurement.component == "carrier_legs"

    start_supervised!(
      {Task,
       fn ->
         send(
           context.test_observer,
           {:usage_incoming_result, handle_event(options, context.service, incoming_event())}
         )
       end}
    )

    assert_receive {:incoming_answer_pending, worker}
    on_exit(fn -> send(worker, :release_incoming_answer) end)

    answered = %{
      answered_event()
      | occurred_at: ~U[2026-09-12 06:00:03.250Z]
    }

    assert :ok = handle_event(context.options, context.service, answered)
    assert_receive {:test_usage_observations, [connected]}
    assert connected.delivery_id == answered.provider_event_id
    send(worker, :release_incoming_answer)
    assert_receive {:usage_incoming_result, {:ok, "wss://voice.example.test/media"}}

    ended = %{
      answered
      | kind: :ended,
        provider_event_id: "event-ended-incoming-usage",
        occurred_at: ~U[2026-09-12 06:01:08.750Z],
        end_reason: :hangup
    }

    assert :ok = handle_event(context.options, context.service, ended)
    assert_receive {:test_usage_observations, [duration]}
    assert duration.outcome == :succeeded
    assert duration.measurement.component == "connection_duration"
    assert duration.measurement.quantity == 65_500
    assert duration.provider.operation_id == claim.provider_call_leg_id
    assert duration.provider.session_id == claim.provider_call_session_id
  end

  test "incoming retries retain exact call identity and initialized service", context do
    service = context.service
    incoming = incoming_event()
    assert :ok = handle_event(context.options, service, incoming)
    assert {:ok, leg} = LegSupervisor.lookup(service.identity, incoming.provider_call_leg_id)

    for owner <- [nil, {:incoming, leg}],
        changed <- [
          %{incoming | provider_call_control_id: "changed-control"},
          %{incoming | provider_call_session_id: "changed-session"}
        ] do
      assert {:error, :telephony_leg_mismatch} =
               handle_event(context.options, service, changed, owner)
    end

    assert :ok =
             handle_event(
               context.options,
               service,
               %{incoming | provider_event_id: "retry-event"},
               {:incoming, leg}
             )
  end

  defp handle_event(options, service, event, owner \\ :lookup) do
    owner =
      if owner == :lookup do
        case LegSupervisor.lookup(service.identity, event.provider_call_leg_id) do
          {:ok, leg} -> {:incoming, leg}
          _missing -> nil
        end
      else
        owner
      end

    CallIngress.handle_event(options, service, event, owner)
  end

  defp identity do
    # Each test owns its registry identity; prior owners may still be retiring.
    suffix = System.unique_integer([:positive])

    options = [
      id: "primary-phone-#{suffix}",
      ingress_key: "ingress_telnyx_#{suffix}",
      scope: {:tenant, "AAAAAAAAAAAAAAAA"},
      provider: :telnyx,
      provider_connection_id: "voice-application-1",
      public_key: Base.encode64(:binary.copy(<<1>>, 32)),
      api_key: "test-key"
    ]

    {:ok, service} =
      ConfiguredService.from_snapshot(
        Vxpipe.Gateway.TestTelephonyServiceRepository.snapshot(options),
        "https://voice.example.test"
      )

    service
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
