defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanCommitter do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.ParticipantSupervisor
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Completion

  alias Vxpipe.CallEngine.RoomAuthority.{
    ConnectionLifecycle,
    FirstMessage,
    ParticipantLifecycle,
    SpeechToSpeech,
    Startup
  }

  def commit_ready(pending, ready, state) do
    enforcers =
      ready.receipts
      |> Enum.flat_map(fn {connection_id, receipt} ->
        connection = Map.fetch!(state.connections, connection_id).pid
        Enum.map(receipt.enforcers, &{&1, connection})
      end)
      |> Enum.uniq()

    with :ok <- validate_private_participant(ready.participant),
         {:ok, snapshot} <-
           Authority.commit_candidate(
             state.media_policy_authority,
             ready.candidate,
             pending.deadline_ms,
             enforcers,
             %{
               owner: pending.task.pid,
               attempt_id: pending.attempt_id,
               deadline_ms: pending.deadline_ms,
               participant_id: pending.request.destination_participant_id
             }
           ) do
      commit_participant(snapshot, pending, ready, state)
    else
      # Authority rejects a stale candidate before any enforcer can adopt it.
      {:error, :stale_candidate} = stale ->
        stale

      {:error, reason} = private
      when reason in [:invalid_private_enforcers, :private_participant_unavailable] ->
        private

      _failed ->
        {:error, :destination_commit_unavailable}
    end
  catch
    :exit, _reason -> {:error, :destination_commit_unavailable}
  end

  defp validate_private_participant(preparation) do
    participant = preparation.snapshot

    if ParticipantSupervisor.registered?(
         participant.tenant_id,
         participant.room_id,
         participant.participant_id,
         preparation.participant_supervisor
       ),
       do: :ok,
       else: {:error, :private_participant_unavailable}
  end

  defp commit_participant(snapshot, pending, ready, state) do
    with true <- snapshot == ready.candidate.snapshot,
         {:ok, _participant, state} <-
           ParticipantLifecycle.commit(ready.participant, state, {:prepared, ready.candidate}) do
      state =
        Enum.reduce(ready.receipts, state, fn _receipt, state ->
          {:ok, _connection, state} =
            ConnectionLifecycle.promote_transfer(pending.attempt_id, state)

          state
        end)

      {:ok,
       %{
         state
         | committed_departures:
             MapSet.put(state.committed_departures, pending.request.source_participant_id)
       }}
    else
      _failed -> {:error, :destination_commit_unavailable}
    end
  end

  def finish_ready(pending, ready, state) do
    request = pending.request
    preparation = pending.preparation
    source_tts = state.text_to_speech_capability
    supervisor = Map.fetch!(state.participant_supervisors, request.source_participant_id)

    state = SpeechToSpeech.release(state)

    state = %{
      state
      | pending_participant_transfer: nil,
        agent_turns: %{},
        held_participant_ids: MapSet.new(),
        first_message: FirstMessage.completed(request.caller_participant_id),
        pending_agent_teardowns:
          Map.put(state.pending_agent_teardowns, request.source_capability, %{
            participant_id: request.source_participant_id,
            participant_supervisor: supervisor
          }),
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

    state = Completion.finish(pending, Completion.result(request), state)

    Enum.each(ready.receipts, fn {id, _receipt} ->
      send(Map.fetch!(state.connections, id).pid, {:vxpipe_transfer_active, pending.attempt_id})
    end)

    _ = Startup.discard_text_to_speech(preparation.text_to_speech, state)
    _ = Startup.discard_text_to_speech(source_tts, state)
    state
  end
end
