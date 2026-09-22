defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.CallerEvents do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{Input, Output}
  alias Vxpipe.CallEngine.Speech.Event

  @maximum_pending 16

  def forward(%{caller_source: source} = state, _event) when source != :sts, do: {:ok, state}

  def forward(state, %Event{kind: :speech_started, turn_ref: key} = event) do
    cond do
      state.held? or not Output.audio_route_permitted?(state, state.human_id, state.agent_id) ->
        {:ok, state}

      Map.has_key?(state.caller_turns, key) ->
        {:ok, state}

      map_size(state.caller_turns) >= @maximum_pending ->
        {:error, :pending_caller_overflow}

      true ->
        turn = %{evidence: evidence(state), final?: false, ended?: false}
        send_event(state, turn, event)
        {:ok, put_turn(state, key, turn)}
    end
  end

  def forward(state, %Event{turn_ref: key} = event) do
    case Map.fetch(state.caller_turns, key) do
      {:ok, turn} ->
        if not state.held? and turn.evidence == evidence(state) and
             Output.audio_route_permitted?(state, state.human_id, state.agent_id) do
          forward_current(state, turn, event)
        else
          {:ok, %{state | caller_turns: Map.delete(state.caller_turns, key)}}
        end

      :error ->
        forward_unassociated_text(state, event)
    end
  end

  # Explicit text input can have submission/transcript evidence without an
  # audio onset. Forwarding that evidence does not authorize a public audio turn.
  defp forward_unassociated_text(state, %Event{kind: :input_transcript} = event) do
    if not state.held? and Output.audio_route_permitted?(state, state.human_id, state.agent_id) and
         Output.transcript_route_permitted?(state, state.human_id, state.agent_id) do
      send_event(state, %{evidence: evidence(state)}, event)
    end

    {:ok, state}
  end

  defp forward_unassociated_text(state, _event), do: {:ok, state}

  defp forward_current(state, turn, %Event{kind: :input_transcript, turn_ref: key} = event) do
    if not turn.final? and
         Output.transcript_route_permitted?(state, state.human_id, state.agent_id) do
      send_event(state, turn, event)
      {:ok, put_turn(state, key, %{turn | final?: event.final != false})}
    else
      {:ok, state}
    end
  end

  defp forward_current(state, turn, %Event{kind: :turn_ended, turn_ref: key} = event) do
    text_allowed? = Output.transcript_route_permitted?(state, state.human_id, state.agent_id)
    text = if text_allowed?, do: event.text
    send_event(state, turn, %{event | text: text})
    final? = turn.final? or not text_allowed? or (is_binary(text) and text != "")
    {:ok, put_turn(state, key, %{turn | ended?: true, final?: final?})}
  end

  defp evidence(state) do
    %{
      identity: Map.put(state.frame_identity, :participant_id, state.human_id),
      epoch: state.input_epoch,
      audio_interval: Input.audio_interval(state, state.human_id),
      transcript_interval: Input.transcript_interval(state, state.human_id)
    }
  end

  defp send_event(state, turn, event),
    do:
      send(state.owner, {:vxpipe_sts_input_event, self(), Map.put(turn.evidence, :event, event)})

  defp put_turn(state, key, %{ended?: true, final?: true}),
    do: %{state | caller_turns: Map.delete(state.caller_turns, key)}

  defp put_turn(state, key, turn),
    do: %{state | caller_turns: Map.put(state.caller_turns, key, turn)}
end
