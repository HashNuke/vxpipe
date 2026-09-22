defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence do
  @moduledoc "Identity and event attribution shared by room-owned STS publications."

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.STSInputHandle
  alias Vxpipe.CallEngine.RoomAuthority.State

  @spec current?(State.t(), pid()) :: boolean()
  def current?(%State{speech_to_speech_capability: %{pid: capability}}, candidate)
      when is_pid(candidate), do: capability == candidate

  def current?(%State{}, _candidate), do: false

  def current_agent?(state, capability, agent_id) do
    current?(state, capability) and state.speech_to_speech_capability.participant_id == agent_id
  end

  def human_connection(state, human_id) do
    Enum.find_value(state.connections, nil, fn {id, connection} ->
      if connection.participant_id == human_id, do: {id, connection}
    end)
  end

  def agent_connection(
        %State{
          speech_to_speech_capability: %{
            connection_id: id,
            connection: owner,
            input_handle: %STSInputHandle{connection: owner, identity: identity}
          }
        } = state
      ) do
    with %{pid: ^owner, role: :human, admission: :main, attach_command: command} = connection <-
           Map.get(state.connections, id),
         expected = %{
           tenant_id: state.snapshot.tenant_id,
           room_id: state.snapshot.room_id,
           incarnation_id: state.snapshot.incarnation_id,
           participant_id: connection.participant_id,
           connection_id: id
         },
         true <- identity == expected,
         true <- Map.take(command, Map.keys(expected)) == expected do
      {id, connection}
    else
      _invalid -> nil
    end
  end

  def agent_connection(%State{}), do: nil

  def connection_id(connection, state) do
    Enum.find_value(state.connections, nil, fn {id, candidate} ->
      if candidate.pid == connection.pid, do: id
    end)
  end

  def turn_key(turn) when is_binary(turn) or is_reference(turn), do: turn

  def agent_participant(state) do
    case state.speech_to_speech_capability do
      %{participant_id: agent_id} -> agent_id
      nil -> "agent"
    end
  end

  def agent_fields(state, _connection, turn) do
    %{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: turn.agent_id,
      source_participant_id: turn.agent_id,
      connection_id: turn.connection_id,
      command_id: turn.command_id,
      correlation_id: turn.correlation_id,
      occurred_at: DateTime.utc_now(:millisecond)
    }
  end
end
