defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.PrivateMedia do
  @moduledoc false

  alias Vxpipe.CallEngine.{Error, RoomAudioHandle}
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.PrivateSpeech

  def bound?(pending, state) do
    Enum.any?(state.connections, fn {_id, connection} ->
      connection.admission == :transfer_preparation and
        connection.transfer_attempt_id == pending.attempt_id and
        Map.get(connection, :private_media?, false)
    end)
  end

  def allocate(command, caller, attempt_id, state) do
    case PrivateSpeech.allocate(command, caller, attempt_id, state) do
      {:reply, {:ok, speech}, state} ->
        case context(command, speech, state) do
          {:ok, context} ->
            connections =
              Map.update!(
                state.connections,
                command.connection_id,
                &Map.put(&1, :private_media?, true)
              )

            {:reply, {:ok, context}, %{state | connections: connections}}

          error ->
            {:reply, error, state}
        end

      other ->
        other
    end
  end

  defp context(command, speech, state) do
    pending = state.pending_participant_transfer

    with {:ok, %RoomAudioHandle{} = handle} <- RoomAudioHandle.resolve(command.incarnation_id),
         policy <- Authority.snapshot(state.media_policy_authority, 1_000),
         false <- MapSet.member?(policy.present_participant_ids, command.participant_id),
         true <- pending.deadline_ms > System.monotonic_time(:millisecond),
         true <- Process.alive?(pending.task.pid) do
      {:ok,
       %{
         owner: pending.task.pid,
         attempt_id: pending.attempt_id,
         deadline_ms: pending.deadline_ms,
         policy: policy,
         policy_authority: state.media_policy_authority,
         participant_id: command.participant_id,
         configuration: handle.configuration,
         output_mode: :mix_minus,
         speech_to_text: speech
       }}
    else
      _unavailable -> {:error, unavailable()}
    end
  catch
    :exit, _reason -> {:error, unavailable()}
  end

  defp unavailable,
    do: Error.new(:private_media_unavailable, "Private transfer media could not be prepared.")
end
