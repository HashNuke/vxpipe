defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.CallerTurns do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted
  }

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.RoomAuthority.{CallerIdle, EventPublisher, SpokenHistory}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence
  alias Vxpipe.CallEngine.Speech.Event

  @maximum_pending 16

  def handle(state, capability, %{event: %Event{sequence: sequence} = event} = evidence, policy)
      when is_integer(sequence) and sequence > 0 do
    if sequence > state.sts_caller_sequence and authorized?(state, capability, evidence, policy) do
      text_allowed? =
        Effective.transcript_route_permitted?(
          policy.effective,
          evidence.identity.participant_id,
          state.speech_to_speech_capability.participant_id
        )

      apply_event(
        %{state | sts_caller_sequence: sequence},
        event,
        Map.delete(evidence, :event),
        text_allowed?
      )
    else
      {:ok, state}
    end
  end

  def handle(state, _capability, _evidence, _policy), do: {:ok, state}

  defp authorized?(state, capability, evidence, %Snapshot{} = policy) do
    with true <- Evidence.current?(state, capability),
         {_, connection} <- Evidence.agent_connection(state),
         %{identity: identity, epoch: epoch, audio_interval: audio, transcript_interval: text} <-
           evidence,
         %{input_handle: handle, input_epoch: ^epoch, participant_id: agent} <-
           state.speech_to_speech_capability,
         true <- is_reference(epoch) and identity == handle.identity,
         true <- Snapshot.valid?(policy),
         true <- MapSet.member?(policy.present_participant_ids, connection.participant_id),
         true <- MapSet.member?(policy.present_participant_ids, agent),
         false <- MapSet.member?(state.held_participant_ids, connection.participant_id),
         nil <- Map.get(state.speech_to_text_runtime, connection.participant_id) do
      audio == Snapshot.interval(policy, :audio_input, connection.participant_id) and
        text == Snapshot.interval(policy, :speech_to_text, connection.participant_id) and
        Effective.audio_route_permitted?(policy.effective, connection.participant_id, agent) and
        text_allowed?(policy, evidence.event, connection.participant_id, agent)
    else
      _invalid -> false
    end
  end

  defp authorized?(_state, _capability, _evidence, _policy), do: false

  defp text_allowed?(policy, %Event{kind: :input_transcript}, source, agent),
    do: Effective.transcript_route_permitted?(policy.effective, source, agent)

  defp text_allowed?(_policy, _event, _source, _agent), do: true

  defp apply_event(state, %Event{kind: :speech_started, turn_ref: key}, evidence, text_allowed?) do
    cond do
      Map.has_key?(state.sts_caller_turns, key) ->
        {:ok, state}

      map_size(state.sts_caller_turns) >= @maximum_pending ->
        {:error, :pending_caller_overflow}

      true ->
        turn = %{
          command_id: Id.generate(:command),
          correlation_id: Id.generate(:turn),
          evidence: evidence,
          text_allowed?: text_allowed?,
          ended?: false,
          final?: false,
          last_text: nil
        }

        state =
          state
          |> CallerIdle.activity()
          |> publish(ParticipantTurnStarted, turn, modality: :audio)

        {:ok, put_turn(state, key, turn)}
    end
  end

  defp apply_event(state, %Event{turn_ref: key} = event, evidence, _text_allowed?) do
    case Map.fetch(state.sts_caller_turns, key) do
      {:ok, %{evidence: ^evidence} = turn} ->
        {state, turn} = update_turn(state, turn, event)
        {:ok, put_turn(state, key, turn)}

      _unknown ->
        {:ok, state}
    end
  end

  # A provider settles a turn whose transcript cannot be attributed with an empty final. It
  # completes the turn's transcript evidence but is not caller text.
  defp update_turn(state, %{final?: false} = turn, %Event{
         kind: :input_transcript,
         text: "",
         final: final?
       })
       when final? != false,
       do: {state, %{turn | final?: true}}

  defp update_turn(state, %{final?: false} = turn, %Event{
         kind: :input_transcript,
         text: text,
         final: final?
       })
       when is_binary(text) do
    if final? != false or text != turn.last_text do
      {publish_text(state, turn, text, final? != false),
       %{turn | final?: final? != false, last_text: text}}
    else
      {state, turn}
    end
  end

  defp update_turn(state, %{ended?: false} = turn, %Event{kind: :turn_ended, text: text} = event) do
    {state, turn} =
      cond do
        not turn.text_allowed? ->
          {state, %{turn | final?: true}}

        not turn.final? and is_binary(text) and text != "" ->
          {publish_text(state, turn, text, true), %{turn | final?: true, last_text: text}}

        true ->
          {state, turn}
      end

    {publish(state, ParticipantTurnCompleted, turn,
       modality: :audio,
       endpointing: event.endpointing
     ), %{turn | ended?: true}}
  end

  defp update_turn(state, turn, _event), do: {state, turn}

  defp publish_text(state, turn, text, final?) do
    event =
      struct!(
        ParticipantTranscription,
        fields(state, turn) ++ [text: text, final: final?, provider_turn_index: 0]
      )

    {_, connection} = Evidence.agent_connection(state)

    {state, _policy, recipients} =
      EventPublisher.publish_transcript_with_recipients(state, connection.pid, event,
        media_policy_revision: turn.evidence.transcript_interval,
        virtual_recipient_participant_id: state.speech_to_speech_capability.participant_id
      )

    agent_id = state.speech_to_speech_capability.participant_id

    if final? and text != "" and recipient?(recipients, agent_id) do
      send(state.speech_to_speech_capability.pid, {
        :vxpipe_sts_published_history,
        self(),
        {:caller, text}
      })
    end

    history =
      if final?,
        do: SpokenHistory.confirm_user(state.spoken_history, text),
        else: state.spoken_history

    %{state | next_sequence: state.next_sequence + 1, spoken_history: history}
  end

  defp publish(state, module, turn, extra) do
    {_, connection} = Evidence.agent_connection(state)
    event = struct!(module, fields(state, turn) ++ extra)
    state = EventPublisher.publish(state, connection.pid, event)
    %{state | next_sequence: state.next_sequence + 1}
  end

  defp fields(state, turn) do
    Map.to_list(turn.evidence.identity) ++
      [
        id: Id.generate(:event),
        sequence: state.next_sequence,
        command_id: turn.command_id,
        correlation_id: turn.correlation_id,
        occurred_at: DateTime.utc_now(:millisecond)
      ]
  end

  defp put_turn(state, key, %{ended?: true, final?: true}),
    do: %{state | sts_caller_turns: Map.delete(state.sts_caller_turns, key)}

  defp put_turn(state, key, turn),
    do: %{state | sts_caller_turns: Map.put(state.sts_caller_turns, key, turn)}

  defp recipient?(:legacy, _target), do: true
  defp recipient?(recipients, target), do: MapSet.member?(recipients, target)
end
