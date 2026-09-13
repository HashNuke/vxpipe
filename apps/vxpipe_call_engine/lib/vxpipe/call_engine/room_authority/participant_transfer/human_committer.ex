defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanCommitter do
  @moduledoc false

  alias Vxpipe.CallEngine.{ConnectionAttachment, RoomAudioHandle}

  alias Vxpipe.CallEngine.RoomAuthority.{
    ConnectionLifecycle,
    FirstMessage,
    ParticipantLifecycle,
    Startup,
    State
  }

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    Completion,
    History,
    HumanPreparation,
    Pending
  }

  @spec commit(Pending.t(), HumanPreparation.t(), State.t()) ::
          {:ok, map(), State.t()} | {:error, :destination_unavailable, State.t()}
  def commit(%Pending{} = pending, %HumanPreparation{} = preparation, %State{} = state) do
    with {:ok, room_audio} <- RoomAudioHandle.resolve(pending.request.incarnation_id),
         {:ok, _destination, state} <-
           ParticipantLifecycle.start(preparation.destination.command, state),
         {:ok, connection, state} <-
           ConnectionLifecycle.promote_transfer(pending.attempt_id, state) do
      commit_available(pending, preparation, connection, room_audio, state)
    else
      {:error, _reason} -> {:error, :destination_unavailable, state}
    end
  end

  defp commit_available(pending, preparation, connection, room_audio, state) do
    request = pending.request
    source_text_to_speech = state.text_to_speech_capability
    source_supervisor = Map.fetch!(state.participant_supervisors, request.source_participant_id)

    attachment = %ConnectionAttachment{
      admission: :main,
      media_ingress: nil,
      room_audio: room_audio,
      room_audio_input_mode: :enabled,
      room_audio_output_mode: :mix_minus,
      room_monitor: connection.room_monitor,
      transfer_attempt_id: nil
    }

    pending_agent_teardowns =
      Map.put(state.pending_agent_teardowns, request.source_capability, %{
        participant_id: request.source_participant_id,
        participant_supervisor: source_supervisor
      })

    pending_connection_promotions =
      Map.put(state.pending_connection_promotions, request.source_participant_id, %{
        attachment: attachment,
        attempt_id: pending.attempt_id,
        connection: connection.pid
      })

    state = %{
      state
      | agent_turns: %{},
        first_message: FirstMessage.completed(request.caller_participant_id),
        pending_agent_teardowns: pending_agent_teardowns,
        pending_connection_promotions: pending_connection_promotions,
        pending_participant_transfer: nil,
        speech_to_text_runtime:
          Map.put(
            state.speech_to_text_runtime,
            request.destination_participant_id,
            preparation.destination.speech_to_text
          ),
        text_capability: nil,
        text_capability_required?: false,
        text_to_speech_capability: nil,
        text_to_speech_runtime: nil
    }

    _ = Startup.discard_text_to_speech(preparation.text_to_speech, state)
    _ = Startup.discard_text_to_speech(source_text_to_speech, state)

    result = Completion.result(request)
    state = History.completed(state, request)
    state = Completion.publish(request, result, state)

    {:ok, result, state}
  end
end
