defmodule Vxpipe.CallEngine.MediaPolicyAdmissionFailureTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    Error,
    RoomMixer,
    TranscriptRouter
  }

  alias Vxpipe.CallEngine.Command.JoinParticipant

  @moduletag capture_log: true

  test "fails room admission closed when the mixer rejects the candidate policy" do
    assert_rejected_admission(:mixer)
  end

  test "fails room admission closed when the transcript router rejects the candidate policy" do
    assert_rejected_admission(:transcript_router)
  end

  defp assert_rejected_admission(component) do
    plan = compile_plan(component)
    assert {:ok, room} = CallEngine.start_call(plan)

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    room_monitor = Process.monitor(room_authority)
    force_future_revision(component, room.incarnation_id)
    specialist = Map.fetch!(plan.participants, "specialist")

    assert {:ok, command} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: specialist.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:error, %Error{code: :room_start_failed}} = CallEngine.join_participant(command)
    assert_receive {:DOWN, ^room_monitor, :process, ^room_authority, :shutdown}, 2_000
  end

  defp force_future_revision(:mixer, incarnation_id) do
    incarnation_id
    |> RoomMixer.whereis()
    |> :sys.replace_state(fn state ->
      policy = %{state.policy | revision: state.policy.revision + 100}
      %{state | policy: policy}
    end)
  end

  defp force_future_revision(:transcript_router, incarnation_id) do
    incarnation_id
    |> TranscriptRouter.whereis()
    |> :sys.replace_state(fn state ->
      current = %{state.current | revision: state.current.revision + 100}
      %{state | current: current}
    end)
  end

  defp compile_plan(component) do
    resource_id = unique_id("policy-failure-#{component}")
    room_id = unique_id("room-policy-failure")

    input = %{
      schema_version: CallSpec.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human_participant(),
        "receiver" => human_participant(),
        "specialist" =>
          Map.put(human_participant(), :while_present, %{
            audio_routes: %{
              "caller" => ["specialist"],
              "specialist" => ["caller"]
            },
            transcript_routes: %{
              "caller" => ["specialist"],
              "specialist" => ["caller"]
            },
            record_audio: false,
            save_transcripts: false
          })
      },
      limits: %{max_duration_ms: 30_000}
    }

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-policy-failure",
               actor_id: "actor-policy-failure",
               call_id: unique_id("call-policy-failure"),
               room_id: room_id
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{
               host_tools: %{}
             })

    plan
  end

  defp human_participant do
    %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: %{}
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
