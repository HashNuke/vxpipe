defmodule Vxpipe.Gateway.WebAdmissionBindingTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall}
  alias Vxpipe.Gateway.{CallAdmission, TestAdmissionBindingRepository}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(
        :fixture,
        {CallEngine.TestSelectiveAgentRuntimeModelProvider, [owner: self()]}
      )

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(original, :agent_runtime, runtime)
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, original) end)
    %{claim: claim()}
  end

  test "binds the full claim and persists start before any participant or provider startup", %{
    claim: claim
  } do
    observer = self()

    callback = fn
      :bind, [^claim, incarnation] ->
        assert_pending(claim)
        send(observer, {:bound, incarnation})
        {:ok, :admit, %{claim | call: %{claim.call | incarnation_id: incarnation}}}

      :started, [bound, incarnation, started_at] ->
        assert_pending(claim)
        assert bound.call.incarnation_id == incarnation
        assert_received {:bound, ^incarnation}
        {:ok, %{bound.call | state: :running, started_at: started_at}}
    end

    assert {:ok, room, participant, started} = CallAdmission.start_call(options(callback), claim)
    assert started.state == :running
    assert %DateTime{} = started.started_at
    assert started.incarnation_id == room.incarnation_id
    assert participant.incarnation_id == room.incarnation_id
    assert_receive {:test_agent_runtime_model_preparing, preparation}, 1_000
    send(preparation, :release_test_agent_runtime_model)
    stop(claim, room.incarnation_id)
  end

  for failure <- [:cancel, :bind_error, :start_error] do
    @failure failure
    test "#{failure} closes the unopened room without startup", %{claim: claim} do
      callback = failure_callback(@failure, claim)

      assert {:admission_error, _reason} = CallAdmission.start_call(options(callback), claim)
      assert_receive {:completion, monitor}
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
      refute_received {:test_agent_runtime_model_preparing, _}
    end
  end

  test "controller death during binding closes its pending room", %{claim: claim} do
    observer = self()

    callback = fn :bind, [^claim, incarnation] ->
      send(observer, {:binding, self(), incarnation})

      receive do
        :unblock -> {:ok, :admit, claim}
      end
    end

    controller =
      start_supervised!({Task, fn -> CallAdmission.start_call(options(callback), claim) end})

    assert_receive {:binding, ^controller, incarnation}, 1_000

    {:ok, monitor} =
      CallEngine.monitor_room_completion(claim.call.tenant_key, claim.call.room_id, incarnation)

    Process.exit(controller, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_received {:test_agent_runtime_model_preparing, _}
  end

  test "managed admission reserves and starts tracking before releasing startup", %{claim: claim} do
    observer = self()

    callback = fn
      :bind_managed, [^claim, incarnation] ->
        assert_pending(claim)

        bound = %{
          claim
          | call: %{claim.call | incarnation_id: incarnation, gateway_cleanup_required: true}
        }

        {:ok, :admit, :new, bound}

      :started, [bound, incarnation, started_at] ->
        assert_pending(claim)

        binding = %{
          tenant_key: bound.call.tenant_key,
          call_id: bound.call.id,
          room_id: bound.call.room_id,
          incarnation_id: incarnation
        }

        assert {:ok, tracker} = Vxpipe.Gateway.CallCleanupSupervisor.lookup(binding)
        send(observer, {:managed_tracker, tracker})
        {:ok, %{bound.call | state: :running, started_at: started_at}}

      :complete, [binding, at] ->
        send(observer, {:cleanup_stored, binding})

        {:ok,
         %{
           claim.call
           | incarnation_id: binding.incarnation_id,
             gateway_cleanup_required: true,
             gateway_cleanup_completed_at: at
         }}
    end

    configured =
      Keyword.merge(options(callback), managed_cleanup: true, publication_enabled: false)

    assert {:ok, room, _participant, started} = CallAdmission.start_call(configured, claim)
    assert started.gateway_cleanup_required
    assert_receive {:managed_tracker, tracker}
    tracker_monitor = Process.monitor(tracker)
    assert_receive {:test_agent_runtime_model_preparing, preparation}, 1_000
    send(preparation, :release_test_agent_runtime_model)
    stop(claim, room.incarnation_id)
    assert_receive {:cleanup_stored, %{incarnation_id: incarnation}}, 1_000
    assert incarnation == room.incarnation_id
    assert_receive {:DOWN, ^tracker_monitor, :process, ^tracker, :normal}, 1_000
  end

  test "managed admission cannot reconstruct an existing reservation with missing tracker", %{
    claim: claim
  } do
    observer = self()

    callback = fn :bind_managed, [^claim, incarnation] ->
      assert_pending(claim)

      {:ok, monitor} =
        CallEngine.monitor_room_completion(claim.call.tenant_key, claim.call.room_id, incarnation)

      send(observer, {:completion, monitor})

      bound = %{
        claim
        | call: %{claim.call | incarnation_id: incarnation, gateway_cleanup_required: true}
      }

      {:ok, :admit, :existing, bound}
    end

    assert {:admission_error, :cleanup_unavailable} =
             CallAdmission.start_call(
               Keyword.put(options(callback), :managed_cleanup, true),
               claim
             )

    assert_receive {:completion, monitor}
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_received {:test_agent_runtime_model_preparing, _}
  end

  defp failure_callback(failure, claim) do
    observer = self()

    fn
      :bind, [^claim, incarnation] ->
        assert_pending(claim)

        {:ok, monitor} =
          CallEngine.monitor_room_completion(
            claim.call.tenant_key,
            claim.call.room_id,
            incarnation
          )

        send(observer, {:completion, monitor})
        bound = %{claim | call: %{claim.call | incarnation_id: incarnation}}

        case failure do
          :cancel -> {:ok, :cancel, bound}
          :bind_error -> {:error, :storage_unavailable}
          :start_error -> {:ok, :admit, bound}
        end

      :started, [_claim, _incarnation, _started_at] ->
        assert failure == :start_error
        assert_pending(claim)
        {:error, :call_not_admitting}
    end
  end

  defp options(callback), do: [call_repository: {TestAdmissionBindingRepository, callback}]

  defp assert_pending(claim) do
    assert {:error, _} =
             CallEngine.participant_snapshot(
               claim.call.tenant_key,
               claim.call.room_id,
               claim.participant_id
             )

    refute_received {:test_agent_runtime_model_preparing, _}
  end

  defp stop(claim, incarnation) do
    {:ok, monitor} =
      CallEngine.monitor_room_completion(claim.call.tenant_key, claim.call.room_id, incarnation)

    :ok = CallEngine.end_call(claim.call.tenant_key, claim.call.room_id, incarnation)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
  end

  defp claim do
    source = %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test:blocked"}}},
      wait_sounds: nil,
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    {:ok, spec} = CallSpec.new(source, resource_id: "binding-test", revision: 1)
    id = "call-#{System.unique_integer([:positive])}"

    {:ok, invocation} =
      CallInvocation.new(
        %{
          call_spec: %{id: "binding-test", revision: 1},
          initial_variables: %{},
          transport: %{type: "web"}
        },
        tenant_id: "binding-tenant",
        actor_id: "binding-actor",
        call_id: id,
        room_id: "room-#{id}"
      )

    {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})

    call = %PreparedCall{
      id: id,
      tenant_key: plan.tenant_id,
      call_spec_id: plan.call_spec_id,
      call_spec_revision: 1,
      schema_version: plan.schema_version,
      participant_routes: %{},
      entry_caller: plan.entry_caller,
      entry_receiver: plan.entry_receiver,
      initial_variables: %{},
      plan: plan,
      plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
      state: :admitting,
      room_id: plan.room_id,
      created_at: DateTime.utc_now(),
      started_at: nil,
      ended_at: nil,
      incarnation_id: nil,
      terminal_reason: nil
    }

    participant = Map.fetch!(plan.participants, plan.entry_caller)

    %AdmissionClaim{
      call: call,
      token_id: "binding-token",
      participant_key: "binding-route",
      participant_ref: plan.entry_caller,
      participant_id: participant.participant_id,
      accepted_at: DateTime.utc_now()
    }
  end
end
