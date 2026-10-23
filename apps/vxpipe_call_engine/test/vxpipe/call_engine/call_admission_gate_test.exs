defmodule Vxpipe.CallEngine.CallAdmissionGateTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, RoomAuthority}

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
    :ok
  end

  for transport <- [:web, :incoming] do
    @transport transport
    test "#{transport} startup waits for the exact controller and releases once" do
      plan = plan(@transport)
      token = make_ref()
      assert {:ok, room} = start_call(plan, call_admission: {self(), token})
      caller = Map.fetch!(plan.participants, plan.entry_caller)

      assert {:error, _} =
               CallEngine.participant_snapshot(
                 plan.tenant_id,
                 plan.room_id,
                 caller.participant_id
               )

      assert :opening_audio = RoomAuthority.input_admission(plan.tenant_id, plan.room_id)
      refute_received {:test_agent_runtime_model_preparing, _}

      for {incarnation, admission_token} <- [{"stale", token}, {room.incarnation_id, make_ref()}] do
        assert {:error, :call_admission_mismatch} =
                 CallEngine.admit_call(plan.tenant_id, plan.room_id, incarnation, admission_token)

        assert {:error, :call_admission_mismatch} =
                 CallEngine.cancel_call_admission(
                   plan.tenant_id,
                   plan.room_id,
                   incarnation,
                   admission_token
                 )
      end

      observer = self()

      stranger =
        start_supervised!(
          {Task,
           fn ->
             send(
               observer,
               {:stranger_release,
                CallEngine.admit_call(plan.tenant_id, plan.room_id, room.incarnation_id, token)}
             )

             send(
               observer,
               {:stranger_cancel,
                CallEngine.cancel_call_admission(
                  plan.tenant_id,
                  plan.room_id,
                  room.incarnation_id,
                  token
                )}
             )
           end}
        )

      monitor = Process.monitor(stranger)
      assert_receive {:stranger_release, {:error, :call_admission_mismatch}}
      assert_receive {:stranger_cancel, {:error, :call_admission_mismatch}}
      assert_receive {:DOWN, ^monitor, :process, ^stranger, _}

      assert :ok = CallEngine.admit_call(plan.tenant_id, plan.room_id, room.incarnation_id, token)
      assert_receive {:test_agent_runtime_model_preparing, preparation}, 1_000
      assert :ok = CallEngine.admit_call(plan.tenant_id, plan.room_id, room.incarnation_id, token)

      assert {:ok, _} =
               CallEngine.participant_snapshot(
                 plan.tenant_id,
                 plan.room_id,
                 caller.participant_id
               )

      refute_received {:test_agent_runtime_model_preparing, _}
      refute_received {:vxpipe_outgoing_submission, _, _}
      send(preparation, :release_test_agent_runtime_model)
      :ok = CallEngine.TestCallStartup.await_prepared(plan)
      refute_received {:vxpipe_outgoing_submission, _, _}
      stop(plan, room)
    end
  end

  test "pending controller death closes the whole room before participant startup" do
    plan = plan(:web)

    controller =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :finish -> :ok
           end
         end}
      )

    assert {:ok, room} = start_call(plan, call_admission: {controller, make_ref()})

    assert {:ok, completion} =
             CallEngine.monitor_room_completion(plan.tenant_id, plan.room_id, room.incarnation_id)

    assert {:ok, authority} =
             CallEngine.monitor_room(plan.tenant_id, plan.room_id, room.incarnation_id)

    send(controller, :finish)
    assert_receive {:DOWN, ^authority, :process, _, {:shutdown, :call_admission_abandoned}}, 1_000
    assert_receive {:DOWN, ^completion, :process, _, _}, 1_000
    refute_received {:test_agent_runtime_model_preparing, _}
  end

  test "controller cancellation and contradictory gate options cannot start entries" do
    plan = plan(:incoming)
    token = make_ref()
    assert {:ok, room} = start_call(plan, call_admission: {self(), token})

    assert {:ok, completion} =
             CallEngine.monitor_room_completion(plan.tenant_id, plan.room_id, room.incarnation_id)

    assert :ok =
             CallEngine.cancel_call_admission(
               plan.tenant_id,
               plan.room_id,
               room.incarnation_id,
               token
             )

    assert_receive {:DOWN, ^completion, :process, _, _}, 1_000
    refute_received {:test_agent_runtime_model_preparing, _}

    assert {:error, _} =
             start_call(plan(:web),
               call_admission: {self(), token},
               outgoing_admission: {self(), token}
             )

    refute_received {:test_agent_runtime_model_preparing, _}
  end

  defp start_call(plan, options) do
    CallEngine.start_call(
      plan,
      Keyword.put(options, :call_lifecycle,
        readiness_timeout_ms: 30_000,
        idle_timeout_ms: 15_000,
        timer: {CallEngine.TestCallLifecycleTimer, [observer: self()]}
      )
    )
  end

  defp stop(plan, room) do
    assert {:ok, monitor} =
             CallEngine.monitor_room_completion(plan.tenant_id, plan.room_id, room.incarnation_id)

    assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
  end

  defp plan(transport) do
    connection =
      if transport == :web,
        do: %{service: "web", mode: "receive", admission: "start_call"},
        else: %{
          service: "primary-phone",
          mode: "receive",
          admission: "start_call",
          number: "+15550001000"
        }

    input = %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test:blocked"}}},
      wait_sounds: nil,
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{type: "human", connection: connection},
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

    assert {:ok, spec} = CallSpec.new(input, resource_id: "gated-startup", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "gated-startup", revision: 1},
                 initial_variables: %{},
                 transport: %{type: if(transport == :web, do: "web", else: "telephony")}
               },
               tenant_id: "tenant-gate",
               actor_id: "actor-gate",
               call_id: "call-#{System.unique_integer([:positive])}",
               room_id: "room-#{System.unique_integer([:positive])}"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
