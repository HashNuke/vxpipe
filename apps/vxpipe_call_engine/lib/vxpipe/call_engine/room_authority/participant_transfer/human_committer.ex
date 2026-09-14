defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanCommitter do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Completion

  alias Vxpipe.CallEngine.RoomAuthority.{
    ConnectionLifecycle,
    FirstMessage,
    ParticipantLifecycle,
    Startup
  }

  def commit_ready(pending, ready, state) do
    required = MapSet.new(ready.graph.resources, & &1.instance)

    enforcers =
      ready.receipts
      |> Map.values()
      |> Enum.flat_map(& &1.enforcers)
      |> Enum.filter(&MapSet.member?(required, &1))
      |> Enum.uniq()

    with {:ok, snapshot} <-
           Authority.commit_candidate(
             state.media_policy_authority,
             ready.candidate,
             pending.deadline_ms,
             enforcers
           ) do
      commit_participant(snapshot, pending, ready, state)
    else
      # Authority rejects a stale candidate before any enforcer can adopt it.
      {:error, :stale_candidate} = stale -> stale
      _failed -> {:error, :destination_commit_unavailable}
    end
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
