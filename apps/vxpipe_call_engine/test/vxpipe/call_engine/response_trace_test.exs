defmodule Vxpipe.CallEngine.ResponseTraceTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.TestResponseTrace
  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State, TextCapability}
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.Event.ParticipantTurnCompleted
  alias Vxpipe.CallEngine.Command.SendText

  test "captures only selected room boundaries, without arguments or content" do
    room = start_supervised!({Agent, fn -> room_state() end})
    probe = start_supervised!({TestResponseTrace, rooms: [room], maximum_events: 4})
    parent = self()
    before_us = System.monotonic_time(:microsecond)
    publish(room, :audio)
    after_us = System.monotonic_time(:microsecond)
    assert {:ok, [completed, dispatched]} = TestResponseTrace.snapshot(probe)
    assert completed.stage == :completed
    assert dispatched.stage == :dispatched
    assert completed.room_id == "room" and completed.correlation_id == "turn"
    assert completed.command_id == "command" and completed.connection_id == "connection"
    assert completed.incarnation_id == "incarnation" and completed.participant_id == "human"
    assert before_us <= completed.at_us and completed.at_us <= dispatched.at_us
    assert dispatched.at_us <= after_us

    assert Enum.sort(Map.keys(completed)) ==
             Enum.sort([
               :stage,
               :at_us,
               :room_id,
               :incarnation_id,
               :participant_id,
               :connection_id,
               :correlation_id,
               :command_id
             ])

    # Calls outside the selected PID and non-audio completion events are excluded.
    EventPublisher.publish(room_state(), self(), event(:audio))
    Agent.get(room, fn state -> EventPublisher.publish(state, parent, event(:text)) end)
    assert {:ok, [^completed, ^dispatched]} = TestResponseTrace.snapshot(probe)
  end

  test "overflow invalidates the probe instead of silently dropping timing samples" do
    room = start_supervised!({Agent, fn -> room_state() end})
    probe = start_supervised!({TestResponseTrace, rooms: [room], maximum_events: 1})
    publish(room, :audio)
    assert {:error, :overflow} = TestResponseTrace.snapshot(probe)
  end

  test "snapshot fences trace messages from an authority that already exited" do
    room = start_supervised!({Agent, fn -> room_state() end})
    probe = start_supervised!({TestResponseTrace, rooms: [room], maximum_events: 2})
    publish(room, :audio)
    monitor = Process.monitor(room)
    stop_supervised!(Agent)
    assert_receive {:DOWN, ^monitor, :process, ^room, _}

    assert {:ok, [%{stage: :completed}, %{stage: :dispatched}]} =
             TestResponseTrace.snapshot(probe)
  end

  def respond(_pid, _command), do: :ok

  defp publish(room, modality) do
    parent = self()

    Agent.get(room, fn state ->
      EventPublisher.publish(state, parent, event(modality))
      TextCapability.respond(%{module: __MODULE__, pid: self()}, command())
    end)
  end

  defp room_state do
    snapshot = %Snapshot{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "create"
    }

    State.new(%Recorder{port: nil, participant_activations: %{}}, snapshot, %{})
  end

  defp event(modality) do
    %ParticipantTurnCompleted{
      id: "event",
      sequence: 1,
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      correlation_id: "turn",
      command_id: "command",
      modality: modality,
      occurred_at: DateTime.utc_now()
    }
  end

  defp command do
    {:ok, command} =
      SendText.new(
        id: "command",
        tenant_id: "tenant",
        actor_id: "actor",
        room_id: "room",
        incarnation_id: "incarnation",
        participant_id: "human",
        connection_id: "connection",
        correlation_id: "turn",
        content: "must not be traced",
        deadline: DateTime.add(DateTime.utc_now(), 10)
      )

    command
  end
end
