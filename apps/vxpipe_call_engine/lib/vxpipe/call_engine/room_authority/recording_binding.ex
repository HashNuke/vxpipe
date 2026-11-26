defmodule Vxpipe.CallEngine.RoomAuthority.RecordingBinding do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.OutputSink
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.RoomMixer

  def bind(participant_id, connection_id, output_sink, state) do
    if recording_permitted?(state, participant_id) do
      bind_recording_egress(participant_id, connection_id, output_sink, state.room_mixer)
    else
      :ok
    end
  end

  defp recording_permitted?(
         %State{
           participant_transfer_runtime: %{
             plan: %{media_policy: %{record_audio: true}, participants: participants}
           }
         },
         participant_id
       )
       when is_binary(participant_id) and is_map(participants) do
    case Enum.find(participants, fn {_key, entry} ->
           is_map(entry) and Map.get(entry, :participant_id) == participant_id
         end) do
      {_key, %{while_present: %{record_audio: false}}} -> false
      {_key, _entry} -> true
      nil -> false
    end
  end

  defp recording_permitted?(%State{participant_transfer_runtime: %{plan: _}}, _participant_id),
    do: false

  defp recording_permitted?(_state, _participant_id), do: true

  defp bind_recording_egress(_participant_id, _connection_id, nil, _room_mixer), do: :ok
  defp bind_recording_egress(_participant_id, _connection_id, _output_sink, nil), do: :ok

  defp bind_recording_egress(participant_id, connection_id, output_sink, room_mixer)
       when is_binary(connection_id) and is_pid(output_sink) and is_pid(room_mixer) do
    case RoomMixer.open_recording_egress(room_mixer, connection_id, participant_id) do
      :disabled ->
        :ok

      {:ok, handoff} ->
        case OutputSink.bind_recording(output_sink, handoff) do
          :ok ->
            :ok

          {:error, _reason} = error ->
            # The just-opened credential never reached the sink. Revoke only
            # that handoff before any PCM can be enqueued; any earlier handoff
            # for the same connection (for example a preparation binding kept
            # across promotion) stays live.
            _ = revoke_recording_handoff(room_mixer, handoff)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  def revoke_connection(nil, _connection_id), do: :ok

  def revoke_connection(room_mixer, connection_id)
      when is_pid(room_mixer) and is_binary(connection_id) do
    _ =
      try do
        RoomMixer.revoke_recording_egress(room_mixer, connection_id)
      catch
        :exit, _ -> {:error, :unavailable}
      end

    :ok
  end

  def revoke_connection(_room_mixer, _connection_id), do: :ok

  defp revoke_recording_handoff(nil, _handoff), do: :ok

  defp revoke_recording_handoff(room_mixer, handoff) when is_pid(room_mixer) do
    _ =
      try do
        RoomMixer.revoke_recording_handoff(room_mixer, handoff)
      catch
        :exit, _ -> {:error, :unavailable}
      end

    :ok
  end

  defp revoke_recording_handoff(_room_mixer, _handoff), do: :ok
end
