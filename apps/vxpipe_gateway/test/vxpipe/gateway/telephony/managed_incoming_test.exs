defmodule Vxpipe.Gateway.Telephony.ManagedIncomingTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Telephony.Event

  alias Vxpipe.Gateway.{
    CallCleanup,
    CallCleanupSupervisor,
    TestManagedIncomingBackend,
    TelephonyCallScenario
  }

  alias Vxpipe.Gateway.Telephony.{ConfiguredService, Leg, LegSupervisor, MediaAdmission}

  setup context do
    media = start_supervised!({MediaAdmission, name: nil})

    scenario =
      TelephonyCallScenario.build(
        :telnyx,
        self(),
        :binary.copy(<<1>>, 32),
        media,
        "managed-incoming-leg",
        "managed-outgoing-leg"
      )

    claim = human_claim(scenario)
    room_id = claim.call.room_id

    {:ok, service} =
      ConfiguredService.from_snapshot(
        Vxpipe.Gateway.TestTelephonyServiceRepository.snapshot(scenario.service_options),
        "https://voice.example.test"
      )

    backend =
      start_supervised!(
        {TestManagedIncomingBackend,
         [
           observer: self(),
           claim: claim,
           runtime_options: scenario.runtime_options,
           media_admission: media
         ] ++
           Map.to_list(
             Map.take(context, [
               :decision,
               :identity_failure?,
               :nil_usage?,
               :bind_error?,
               :reservation,
               :block_end?
             ])
           )}
      )

    event = %Event{
      kind: :incoming,
      provider: claim.provider,
      provider_event_id: claim.provider_event_id,
      provider_connection_id: claim.provider_connection_id,
      provider_call_control_id: claim.provider_call_control_id,
      provider_call_leg_id: claim.provider_call_leg_id,
      provider_call_session_id: claim.provider_call_session_id,
      occurred_at: DateTime.utc_now(),
      occurred_at_provenance: :provider_reported
    }

    on_exit(fn ->
      LegSupervisor.stop(service.identity, event.provider_call_leg_id)

      updated =
        try do
          TestManagedIncomingBackend.state(backend).claim
        rescue
          _ -> claim
        catch
          :exit, _ -> claim
        end

      if updated.call.incarnation_id,
        do: CallEngine.end_call(claim.call.tenant_key, room_id, updated.call.incarnation_id)

      binding = %{
        tenant_key: claim.call.tenant_key,
        call_id: claim.call.id,
        room_id: room_id,
        incarnation_id: updated.call.incarnation_id
      }

      case CallCleanupSupervisor.lookup(binding) do
        {:ok, tracker} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
        _ -> :ok
      end
    end)

    %{backend: backend, service: service, event: event}
  end

  test "seeds original ownership before identity and carries binding into prepared media", c do
    leg = start_leg(c)
    assert {:ok, _media_url} = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, binding, {:ok, tracker}}

    assert %{resources: %{^leg => %{owner: ^leg, acknowledgement: :pending}}} =
             CallCleanup.snapshot(tracker)

    assert_receive {:preparing_incoming, media_binding}
    assert media_binding.cleanup_binding == binding
    leg_monitor = Process.monitor(leg)
    tracker_monitor = Process.monitor(tracker)
    ended(c, leg)
    assert_receive {:incoming_usage_store, worker, first}

    assert %{completed_at: nil, resources: %{^leg => %{acknowledgement: :pending}}} =
             CallCleanup.snapshot(tracker)

    refute_receive {:DOWN, ^leg_monitor, :process, ^leg, _}
    send(worker, :store)
    assert_receive {:incoming_usage_store, ^worker, terminal}
    assert terminal.attempt_id == first.attempt_id
    send(worker, :store)
    assert_receive {:DOWN, ^leg_monitor, :process, ^leg, :normal}, 1_000
    assert_receive {:incoming_cleanup_completed, ^binding, %DateTime{}}, 1_000
    assert_receive {:DOWN, ^tracker_monitor, :process, ^tracker, :normal}, 1_000
  end

  @tag decision: :cancel, block_end?: true
  test "cancellation retains usage and waits for end-command drainage after final storage", c do
    leg = start_leg(c)
    assert :ok = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, binding, {:ok, tracker}}
    assert_receive {:incoming_end, command, "inbound-call-control"}
    monitor = Process.monitor(leg)
    tracker_monitor = Process.monitor(tracker)
    ended(c, leg)
    store_final_batch()
    assert %{resources: %{^leg => %{acknowledgement: :pending}}} = CallCleanup.snapshot(tracker)
    refute_receive {:DOWN, ^monitor, :process, ^leg, _}
    send(command, :finish_end)
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    assert_receive {:incoming_cleanup_completed, ^binding, _}, 1_000
    assert_receive {:DOWN, ^tracker_monitor, :process, ^tracker, :normal}, 1_000
    refute_received {:preparing_incoming, _}
  end

  test "tracker loss closes the original carrier then stores usage without manufacturing completion",
       c do
    leg = start_leg(c)
    assert {:ok, _} = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, binding, {:ok, tracker}}
    Process.exit(tracker, :kill)
    assert_receive {:incoming_end, _command, "inbound-call-control"}, 1_000
    monitor = Process.monitor(leg)
    ended(c, leg)
    store_final_batch()
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    refute_received {:incoming_cleanup_completed, _, _}
  end

  @tag identity_failure?: true
  test "identity failure keeps seeded cleanup unresolved after authenticated carrier end", c do
    leg = start_leg(c)
    assert :ok = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, _binding, {:ok, tracker}}
    on_exit(fn -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker) end)
    assert_receive {:incoming_end, _, "inbound-call-control"}
    monitor = Process.monitor(leg)
    ended(c, leg)
    send(leg, :retire)
    assert :ok = Leg.await(leg, 1_000)
    refute_receive {:DOWN, ^monitor, :process, ^leg, _}
    assert %{resources: %{^leg => %{acknowledgement: :pending}}} = CallCleanup.snapshot(tracker)
    refute_received {:incoming_usage_store, _, _}
    refute_received {:incoming_cleanup_completed, _, _}
  end

  @tag bind_error?: true
  test "reservation failure retains managed marker and cannot fall back to legacy retirement",
       c do
    leg = start_leg(c)
    assert :ok = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, binding, {:error, :not_found}}
    assert_receive {:incoming_end, _, "inbound-call-control"}
    monitor = Process.monitor(leg)
    ended(c, leg)
    send(leg, :retire)
    assert :ok = Leg.await(leg, 1_000)
    refute_receive {:DOWN, ^monitor, :process, ^leg, _}
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    refute_received {:incoming_cleanup_completed, _, _}
  end

  @tag nil_usage?: true
  test "a retained identity without usage cannot prepare media or acknowledge completion", c do
    leg = start_leg(c)
    assert :ok = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, _binding, {:ok, tracker}}
    on_exit(fn -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker) end)
    assert_receive {:incoming_end, _, "inbound-call-control"}
    monitor = Process.monitor(leg)
    ended(c, leg)
    send(leg, :retire)
    assert :ok = Leg.await(leg, 1_000)
    refute_receive {:DOWN, ^monitor, :process, ^leg, _}
    assert %{resources: %{^leg => %{acknowledgement: :pending}}} = CallCleanup.snapshot(tracker)
    refute_received {:preparing_incoming, _}
    refute_received {:incoming_usage_store, _, _}
    refute_received {:incoming_cleanup_completed, _, _}
  end

  @tag decision: :cancel, block_end?: true
  test "stored terminal usage cannot replace missing command drainage evidence", c do
    leg = start_leg(c)
    assert :ok = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, _binding, {:ok, tracker}}
    on_exit(fn -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker) end)
    assert_receive {:incoming_end, operation, "inbound-call-control"}
    on_exit(fn -> send(operation, :finish_end) end)
    {:monitored_by, [observer]} = Process.info(operation, :monitored_by)
    observer_monitor = Process.monitor(observer)
    Process.exit(observer, :kill)
    assert_receive {:DOWN, ^observer_monitor, :process, ^observer, :killed}
    monitor = Process.monitor(leg)
    ended(c, leg)
    store_final_batch()
    send(operation, :finish_end)
    send(leg, :retire)
    assert :ok = Leg.await(leg, 1_000)
    refute_receive {:DOWN, ^monitor, :process, ^leg, _}
    assert %{resources: %{^leg => %{acknowledgement: :pending}}} = CallCleanup.snapshot(tracker)
    refute_received {:incoming_cleanup_completed, _, _}
  end

  @tag reservation: :existing
  test "a missing previously reserved tracker stays detached and is never recreated", c do
    leg = start_leg(c)
    assert :ok = Leg.await(leg, 1_000)
    assert_receive {:identifying_incoming, ^leg, binding, {:error, :not_found}}
    assert_receive {:incoming_end, _, "inbound-call-control"}
    monitor = Process.monitor(leg)
    ended(c, leg)
    store_final_batch()
    assert_receive {:DOWN, ^monitor, :process, ^leg, :normal}, 1_000
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    refute_received {:incoming_cleanup_completed, _, _}
  end

  defp human_claim(scenario) do
    alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}
    old = scenario.plan

    {:ok, spec} =
      CallSpec.new(
        %{
          schema_version: "20260915.01",
          entry_caller: "caller",
          entry_receiver: "listener",
          defaults: %{capabilities: %{}},
          participants: %{
            "caller" => %{
              type: "human",
              connection: %{
                service: "primary-phone",
                mode: "receive",
                admission: "start_call",
                number: "+15550001000"
              }
            },
            "listener" => %{
              type: "human",
              connection: %{service: "web", mode: "receive", admission: "start_call"}
            }
          },
          limits: %{max_duration_ms: 60_000}
        },
        resource_id: old.call_spec_id,
        revision: 1
      )

    {:ok, invocation} =
      CallInvocation.new(
        %{
          call_spec: %{id: old.call_spec_id, revision: 1},
          initial_variables: %{},
          transport: %{type: "telephony"}
        },
        tenant_id: old.tenant_id,
        actor_id: old.actor_id,
        call_id: old.call_id,
        room_id: old.room_id
      )

    {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan = Vxpipe.Gateway.TestTelephonyServiceRepository.pin_plan(plan, scenario.service_options)

    %{
      scenario.claim
      | participant_id: Map.fetch!(plan.participants, "caller").participant_id,
        call: %{
          scenario.claim.call
          | plan: plan,
            plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
            entry_receiver: plan.entry_receiver
        }
    }
  end

  defp start_leg(c) do
    {:ok, leg} =
      LegSupervisor.start(
        LegSupervisor,
        c.service,
        c.event,
        TestManagedIncomingBackend.backend(c.backend),
        &DateTime.utc_now/0
      )

    leg
  end

  defp ended(c, leg),
    do: assert(:ok == Leg.dispatch(leg, %{c.event | kind: :ended, end_reason: :hangup}, 1_000))

  defp store_final_batch do
    assert_receive {:incoming_usage_store, worker, _started}, 1_000
    send(worker, :store)
    assert_receive {:incoming_usage_store, ^worker, _terminal}, 1_000
    send(worker, :store)
  end
end
