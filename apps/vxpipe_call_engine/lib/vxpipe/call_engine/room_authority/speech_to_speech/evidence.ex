defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence do
  @moduledoc "Identity and event attribution shared by room-owned STS publications."

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Effective, Snapshot}
  alias Vxpipe.CallEngine.STSInputHandle
  alias Vxpipe.CallEngine.RoomAuthority.State

  @spec current?(State.t(), pid()) :: boolean()
  def current?(%State{speech_to_speech_capability: %{pid: capability}}, candidate)
      when is_pid(candidate), do: capability == candidate

  def current?(%State{}, _candidate), do: false

  def current_agent?(state, capability, agent_id) do
    current?(state, capability) and state.speech_to_speech_capability.participant_id == agent_id
  end

  def policy_snapshot(%State{media_policy_authority: authority}) when is_pid(authority) do
    Authority.snapshot(authority)
  catch
    :exit, _reason -> nil
  end

  def policy_snapshot(%State{}), do: nil

  def tool_scope_current?(state, evidence),
    do: tool_scope_current?(state, evidence, policy_snapshot(state))

  def tool_scope_current?(state, evidence, %Snapshot{} = policy) do
    with %{identity: identity, epoch: epoch, audio_interval: interval} <- evidence,
         %{input_handle: handle, input_epoch: ^epoch, participant_id: agent} <-
           state.speech_to_speech_capability,
         true <- is_reference(epoch) and identity == handle.identity,
         {_, connection} <- agent_connection(state),
         false <- MapSet.member?(state.held_participant_ids, connection.participant_id),
         true <- Snapshot.valid?(policy),
         true <- MapSet.member?(policy.present_participant_ids, connection.participant_id),
         true <- MapSet.member?(policy.present_participant_ids, agent) do
      interval == Snapshot.interval(policy, :audio_input, connection.participant_id) and
        Effective.audio_route_permitted?(policy.effective, connection.participant_id, agent)
    else
      _invalid -> false
    end
  end

  def tool_scope_current?(_state, _evidence, _policy), do: false

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
