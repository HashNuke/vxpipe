defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Committer do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator, as: AgentRuntimeCoordinator
  alias Vxpipe.CallEngine.Event.ToolCallCompleted
  alias Vxpipe.CallEngine.Id

  alias Vxpipe.CallEngine.RoomAuthority.{
    EventPublisher,
    ParticipantLifecycle,
    Startup,
    State
  }

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.{Pending, Preparation}

  @spec commit(Pending.t(), Preparation.t(), State.t()) :: {map(), State.t()}
  def commit(%Pending{} = pending, %Preparation{} = preparation, %State{} = state) do
    request = pending.request

    {:ok, destination_snapshot, state} =
      ParticipantLifecycle.commit(preparation.participant, state)

    source_text_to_speech = state.text_to_speech_capability
    source_supervisor = Map.fetch!(state.participant_supervisors, request.source_participant_id)

    destination_capability = %{
      activation_id: preparation.destination.participant.activation_id,
      module: AgentRuntimeCoordinator,
      monitor: nil,
      participant_id: destination_snapshot.participant_id,
      pid:
        AgentActivationSupervisor.child_ref(
          preparation.destination.participant.activation_id,
          :coordinator
        )
    }

    pending_agent_teardowns =
      Map.put(state.pending_agent_teardowns, request.source_capability, %{
        participant_id: request.source_participant_id,
        participant_supervisor: source_supervisor
      })

    state = %{
      state
      | agent_turns: %{},
        pending_agent_teardowns: pending_agent_teardowns,
        pending_agent_transfer: nil,
        text_capability: destination_capability,
        text_to_speech_capability: Startup.activate_text_to_speech(preparation.text_to_speech)
    }

    _ = Startup.discard_text_to_speech(source_text_to_speech, state)

    result = %{
      "destination" => request.destination_definition_key,
      "status" => "completed"
    }

    {result, publish_completed(request, result, state)}
  end

  defp publish_completed(request, result, state) do
    connection = Map.fetch!(state.connections, request.connection_id)

    event = %ToolCallCompleted{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: request.tenant_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.source_participant_id,
      source_participant_id: request.caller_participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      tool_call_id: request.tool_call_id,
      name: "transfer",
      result: result,
      occurred_at: DateTime.utc_now(:millisecond)
    }

    state
    |> EventPublisher.publish(connection.pid, event)
    |> Map.update!(:background_tool_calls, &Map.delete(&1, request.tool_call_id))
    |> Map.update!(:next_sequence, &(&1 + 1))
  end
end
