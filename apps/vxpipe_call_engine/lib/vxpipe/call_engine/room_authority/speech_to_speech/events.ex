defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Events do
  @moduledoc false
  alias Vxpipe.CallEngine.RoomAuthority.{CallerIdle, SpeechToSpeech, StartupReadiness}

  def handle({:vxpipe_sts_ready, capability}, state) do
    if SpeechToSpeech.current?(state, capability) do
      state = SpeechToSpeech.handle_ready(state, capability)
      StartupReadiness.reply(StartupReadiness.ready(state), state)
    else
      {:noreply, state}
    end
  end

  def handle({:vxpipe_sts_speech_started, capability, agent_id, turn}, state) do
    {:noreply, SpeechToSpeech.handle_speech_started(state, capability, agent_id, turn)}
  end

  def handle({:vxpipe_sts_input_event, capability, evidence}, state) do
    {:noreply, SpeechToSpeech.handle_input_event(state, capability, evidence)}
  end

  def handle({:vxpipe_sts_turn_started, capability, agent_id, turn, sequence}, state) do
    {:noreply, SpeechToSpeech.handle_turn_started(state, capability, agent_id, turn, sequence)}
  end

  def handle(
        {:vxpipe_sts_agent_transcript, capability, agent_id, text, turn, played, interval,
         sequence},
        state
      ) do
    {:noreply,
     SpeechToSpeech.handle_agent_transcript(
       state,
       capability,
       agent_id,
       text,
       turn,
       played,
       interval,
       sequence
     )}
  end

  def handle({:vxpipe_sts_turn_completed, capability, agent_id, turn, sequence}, state) do
    {:noreply,
     CallerIdle.reconcile(
       SpeechToSpeech.handle_turn_completed(state, capability, agent_id, turn, sequence)
     )}
  end

  def handle(
        {:vxpipe_sts_interrupted, capability, agent_id, turn, played, prefix, sequence},
        state
      ) do
    {:noreply,
     CallerIdle.reconcile(
       SpeechToSpeech.handle_interrupted(
         state,
         capability,
         agent_id,
         turn,
         played,
         prefix,
         sequence
       )
     )}
  end

  def handle({:vxpipe_sts_tool_event, capability, agent_id, evidence}, state) do
    {:noreply, SpeechToSpeech.handle_tool_event(state, capability, agent_id, evidence)}
  end

  def handle({:vxpipe_sts_tool_executed, capability, call_ref, outcome}, state) do
    {:noreply, SpeechToSpeech.handle_tool_executed(state, capability, call_ref, outcome)}
  end

  def handle({:vxpipe_sts_tool_completion, bridge, lease}, state) do
    {:noreply,
     Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Tools.handle_completion(state, bridge, lease)}
  end

  def handle({:vxpipe_sts_tool_timeout, capability, call_ref}, state) do
    {:noreply, SpeechToSpeech.handle_tool_timeout(state, capability, call_ref)}
  end

  # Output-STT recognition problems are observability only at the room
  # boundary: the turn outcome (completed/interrupted with or without text)
  # already settles through the dedicated turn messages above.
  def handle({:vxpipe_sts_output_stt_unavailable, _capability, _reason}, state) do
    {:noreply, state}
  end

  def handle({:vxpipe_sts_unavailable, capability, reason}, state) do
    state = SpeechToSpeech.handle_unavailable(state, capability, reason)
    {:noreply, CallerIdle.reconcile(state)}
  end

  def handle(_invalid, state), do: {:noreply, state}
end
