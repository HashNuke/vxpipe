defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.AgentTranscript do
  @moduledoc "Publishes playback-qualified STS agent text on the room timeline."

  alias Vxpipe.CallEngine.Event.TextOutput
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence

  import Evidence, only: [agent_connection: 1, turn_key: 1]

  @spec publish(
          State.t(),
          pid(),
          String.t(),
          String.t(),
          binary() | reference(),
          non_neg_integer(),
          non_neg_integer(),
          pos_integer()
        ) :: State.t()
  def publish(
        %State{} = state,
        capability,
        agent_id,
        text,
        provider_turn,
        played_ms,
        interval,
        sequence
      )
      when is_binary(agent_id) and is_binary(text) and
             (is_binary(provider_turn) or is_reference(provider_turn)) and
             is_integer(played_ms) do
    with true <- Evidence.current_agent?(state, capability, agent_id),
         {:ok, %{agent_id: ^agent_id, source_sequence: ^sequence, text_published?: false} = turn} <-
           Map.fetch(state.sts_turns, turn_key(provider_turn)),
         {connection_id, connection} <- agent_connection(state),
         true <- connection_id == turn.connection_id and connection.pid == turn.connection do
      event = %TextOutput{
        id: Id.generate(:event),
        sequence: state.next_sequence,
        tenant_id: state.snapshot.tenant_id,
        room_id: state.snapshot.room_id,
        incarnation_id: state.snapshot.incarnation_id,
        participant_id: agent_id,
        source_participant_id: agent_id,
        connection_id: turn.connection_id,
        command_id: turn.command_id,
        correlation_id: turn.correlation_id,
        text: text,
        aggregated_by: :sentence,
        will_be_spoken: true,
        occurred_at: DateTime.utc_now(:millisecond)
      }

      {state, _policy, recipients} =
        EventPublisher.publish_transcript_with_recipients(state, connection.pid, event,
          media_policy_revision: interval
        )

      if text != "" and recipient?(recipients, connection.participant_id) do
        send(capability, {:vxpipe_sts_published_history, self(), {:agent, text}})
      end

      %{
        state
        | next_sequence: state.next_sequence + 1,
          sts_turns:
            Map.put(state.sts_turns, turn_key(provider_turn), %{turn | text_published?: true})
      }
    else
      _stale -> state
    end
  end

  @spec publish_prefix(
          State.t(),
          pid(),
          String.t(),
          binary() | reference(),
          non_neg_integer(),
          term(),
          pos_integer()
        ) :: State.t()
  def publish_prefix(
        state,
        capability,
        agent_id,
        provider_turn,
        played_ms,
        {:aligned_prefix, text, interval},
        sequence
      )
      when played_ms > 0 and is_binary(text) and text != "" and is_integer(interval) do
    publish(state, capability, agent_id, text, provider_turn, played_ms, interval, sequence)
  end

  def publish_prefix(
        state,
        _capability,
        _agent_id,
        _provider_turn,
        _played_ms,
        _prefix,
        _sequence
      ),
      do: state

  defp recipient?(:legacy, _target), do: true
  defp recipient?(recipients, target), do: MapSet.member?(recipients, target)
end
