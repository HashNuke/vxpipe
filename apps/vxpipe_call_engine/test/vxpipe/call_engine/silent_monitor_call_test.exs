defmodule Vxpipe.CallEngine.SilentMonitorCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    ConnectionAttachment,
    DefinitionCompiler
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, JoinParticipant}
  alias Vxpipe.CallEngine.Media.NormalizedFrame

  test "an admitted monitor receives full mix but cannot publish room audio" do
    plan = compile_plan()
    assert {:ok, room} = CallEngine.start_call(plan)
    stop_room_on_exit(plan)

    monitor = Map.fetch!(plan.participants, "monitor")

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: monitor.participant_id,
               role: :monitor,
               deadline: deadline()
             )

    assert {:ok, _participant} = CallEngine.join_participant(join)

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: monitor.participant_id,
               connection_id: "conn-monitor",
               deadline: deadline()
             )

    assert {:ok,
            %ConnectionAttachment{
              media_ingress: nil,
              room_audio_input_mode: :disabled,
              room_audio_output_mode: :full_mix
            } = attachment} = CallEngine.attach_connection(attach)

    assert :disabled = CallEngine.room_audio_configuration(attachment)
    assert {:ok, %{mode: :full_mix}} = CallEngine.room_audio_output_configuration(attachment)

    assert {:error, :disabled} =
             CallEngine.push_room_audio(
               attachment,
               %NormalizedFrame{
                 tenant_id: plan.tenant_id,
                 room_id: plan.room_id,
                 incarnation_id: room.incarnation_id,
                 source_participant_id: monitor.participant_id,
                 connection_id: "conn-monitor",
                 track_id: "track-monitor",
                 sequence_number: 1,
                 timestamp: 0,
                 policy_revision: 3,
                 sample_rate: 48_000,
                 channels: 1,
                 payload: :binary.copy(<<100::little-signed-16>>, 960)
               }
             )

    assert {:ok, subscription} =
             CallEngine.subscribe_room_audio(attachment,
               id: "monitor-output",
               tenant_id: plan.tenant_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               recipient_participant_id: monitor.participant_id,
               mode: :mix_minus,
               subscriber: self()
             )

    assert subscription.mode == :full_mix
  end

  defp compile_plan do
    resource_id = unique_id("silent-monitor")
    room_id = unique_id("room-silent-monitor")

    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human_participant(),
        "receiver" => human_participant(),
        "monitor" => human_participant()
      },
      limits: %{max_duration_ms: 30_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-silent-monitor",
               actor_id: "actor-silent-monitor",
               call_id: unique_id("call-silent-monitor"),
               room_id: room_id
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
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

  defp deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp stop_room_on_exit(plan) do
    on_exit(fn ->
      case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) do
        [{room, _value}] -> GenServer.stop(room, :shutdown)
        [] -> :ok
      end
    end)
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
