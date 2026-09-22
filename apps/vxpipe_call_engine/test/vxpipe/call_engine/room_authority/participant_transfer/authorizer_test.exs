defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.AuthorizerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Room.Snapshot, as: RoomSnapshot
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{Authorizer, Runtime}
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @tenant "tenant-transfer"
  @room "room-transfer"
  @incarnation "incarnation-transfer"

  test "STS-voiced source agents authorize without a text capability" do
    stub = start_supervised!({Agent, fn -> :ok end})
    state = state(%{pid: stub, participant_id: "agent1"}, "act1")
    request = request(stub, "act1")

    assert :ok = Authorizer.authorize(request, state)
  end

  test "transfer rejects when neither text nor STS voice matches" do
    other = spawn(fn -> :ok end)
    state = state(%{pid: other, participant_id: "agent1"}, "act1")
    request = request(other, "stale-activation")

    assert {:error, :rejected} = Authorizer.authorize(request, state)
  end

  defp state(sts_capability, activation_id) do
    recorder = %Recorder{port: nil, participant_activations: %{"agent1" => activation_id}}

    snapshot = %RoomSnapshot{
      tenant_id: @tenant,
      room_id: @room,
      incarnation_id: @incarnation,
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "command"
    }

    base = State.new(recorder, snapshot, %{})

    plan = %{
      participants: %{
        "agent" => %{kind: :agent, participant_id: "agent1", transfers: ["billing"]},
        "billing" => %{kind: :agent, participant_id: "billing1"}
      },
      entry_caller: "caller"
    }

    %{
      base
      | connections: %{"conn1" => %{participant_id: "human1", pid: self()}},
        participant_ids: MapSet.new(["human1", "agent1"]),
        text_capability: nil,
        speech_to_speech_capability: sts_capability,
        speech_to_speech_runtime: %{participant_id: "agent1", activation_id: activation_id},
        participant_transfer_runtime: %Runtime{plan: plan, startup_options: []}
    }
  end

  defp request(source_capability, activation_id) do
    %Request{
      tenant_id: @tenant,
      room_id: @room,
      incarnation_id: @incarnation,
      source_call_spec_key: "agent",
      source_participant_id: "agent1",
      source_activation_id: activation_id,
      source_capability: source_capability,
      caller_participant_id: "human1",
      connection_id: "conn1",
      command_id: "command-1",
      correlation_id: "correlation-1",
      tool_call_id: "tool-1",
      destination_call_spec_key: "billing",
      destination_participant_id: "billing1",
      reason: nil
    }
  end
end
