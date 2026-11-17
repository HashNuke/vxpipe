defmodule Vxpipe.CallEngine.RoomAuthority.IdleHoldTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomAuthority.{IdleWait, State}
  alias Vxpipe.CallEngine.Tool.Context

  test "transfer-held source retires an existing quiet operation during reconciliation" do
    state = held_state()
    assert IdleWait.reconcile(state).idle_wait == nil
  end

  test "quiet deadline rechecks a newly held source before publishing expiry" do
    state = held_state()
    token = state.idle_wait.token
    next = IdleWait.deadline(token, :quiet, state)
    refute_receive {:vxpipe_idle_expired, _, ^token, _}
    assert next.idle_wait == nil
    refute_received {_, {:ok, %{"status" => "expired"}}}
  end

  defp held_state do
    context = %Context{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      agent_participant_id: "agent",
      source_participant_id: "human",
      connection_id: "connection",
      command_id: "command",
      correlation_id: "turn",
      agent_request_id: "request",
      tool_call_id: "idle-one"
    }

    wait = %IdleWait{
      token: make_ref(),
      context: context,
      coordinator: self(),
      activation_id: "activation",
      worker: self(),
      worker_monitor: nil,
      from: {self(), make_ref()},
      duration_ms: 1000,
      timer: nil,
      phase: :quiet
    }

    state =
      State.new(
        %Recorder{port: nil, participant_activations: %{}},
        %Snapshot{
          tenant_id: "tenant",
          room_id: "room",
          incarnation_id: "incarnation",
          lifecycle: :open,
          created_by_actor_id: "actor",
          created_by_command_id: "command"
        },
        %{}
      )

    %{
      state
      | idle_wait: wait,
        participant_ids: MapSet.new(["human", "agent"]),
        held_participant_ids: MapSet.new(["human"]),
        text_capability: %{
          module: Vxpipe.CallEngine.AgentRuntime.Coordinator,
          participant_id: "agent",
          pid: self(),
          activation_id: "activation"
        },
        connections: %{"connection" => %{participant_id: "human", actor_id: "actor", pid: self()}}
    }
  end
end
