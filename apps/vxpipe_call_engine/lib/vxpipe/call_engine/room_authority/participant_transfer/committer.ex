defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Committer do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.AgentRuntime.Coordinator, as: AgentRuntimeCoordinator

  alias Vxpipe.CallEngine.RoomAuthority.{
    FirstMessage,
    Startup,
    State
  }

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    Completion,
    Pending
  }

  def finish_ready(%Pending{} = pending, %State{} = state) do
    preparation = pending.preparation

    {:ok, result, state} =
      commit_available(pending.request, preparation, preparation.participant.snapshot, state)

    Completion.finish(pending, result, %{state | held_participant_ids: MapSet.new()})
  end

  defp commit_available(request, preparation, destination_snapshot, state) do
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
        first_message:
          FirstMessage.for_agent_activation(
            preparation.destination.participant,
            request.caller_participant_id,
            preparation.first_activation?
          ),
        pending_agent_teardowns: pending_agent_teardowns,
        pending_participant_transfer: nil,
        text_capability: destination_capability,
        text_to_speech_capability: preparation.text_to_speech,
        text_to_speech_runtime: preparation.destination.text_to_speech
    }

    _ = Startup.discard_text_to_speech(source_text_to_speech, state)

    result = Completion.result(request)

    {:ok, result, state}
  end
end
