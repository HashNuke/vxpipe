defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.ActivityControl do
  @moduledoc "Room admission of selected human-STT boundaries to one STS input."

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.STSIngress
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.SpeechToSpeechRuntime

  def start(%State{} = state, connection_id, signal) do
    with mode when mode in ["external", "hybrid"] <- mode(state),
         {:ok, binding} <- current(state, connection_id, signal),
         true <- is_reference(signal.turn_ref),
         nil <- Map.get(binding, :activity_turn) do
      case admit_start(mode, binding, signal) do
        :ok ->
          turn = %{
            source: connection_id,
            turn_ref: signal.turn_ref,
            generation: signal.allocation_generation,
            epoch: binding.input_epoch,
            intervals: intervals(signal)
          }

          put_turn(state, turn)

        {:error, _reason} ->
          SpeechToSpeech.stop(state)
      end
    else
      _not_current -> state
    end
  end

  def finish(%State{} = state, connection_id, signal) do
    with mode when mode in ["external", "hybrid"] <- mode(state),
         %{activity_turn: turn} = binding when is_map(turn) <- state.speech_to_speech_capability,
         true <- turn.source == connection_id and turn.turn_ref == signal.turn_ref,
         true <- turn.generation == signal.allocation_generation,
         true <- turn.epoch == binding.input_epoch and turn.intervals == intervals(signal),
         {:ok, ^binding} <- current(state, connection_id, signal) do
      case STSIngress.activity(binding.ingress, :ended, turn.epoch, turn.intervals) do
        :ok -> put_turn(state, nil)
        {:error, _reason} -> SpeechToSpeech.stop(state)
      end
    else
      _not_current -> state
    end
  end

  defp admit_start("hybrid", _binding, _signal), do: :ok

  defp admit_start("external", binding, signal) do
    STSIngress.activity(binding.ingress, :started, binding.input_epoch, intervals(signal))
  end

  defp current(state, connection_id, signal) do
    with {^connection_id, connection} <- Evidence.agent_connection(state),
         %{speech_to_text: %{capability: stt}} <- connection,
         %{input_epoch: epoch, ingress: ingress, participant_id: agent} = binding <-
           state.speech_to_speech_capability,
         true <- is_reference(epoch) and is_pid(ingress),
         false <- MapSet.member?(state.held_participant_ids, connection.participant_id),
         {:ok, %{activity_origin: %{agent_id: ^agent} = origin}} <-
           SpeechToText.input_binding(stt),
         true <- same_origin?(signal, origin),
         %Snapshot{} = policy <- Evidence.policy_snapshot(state),
         true <- permitted?(policy, connection.participant_id, agent, signal) do
      {:ok, binding}
    else
      _invalid -> {:error, :stale_activity}
    end
  end

  defp permitted?(%Snapshot{} = policy, source, agent, signal) do
    Snapshot.valid?(policy) and
      MapSet.member?(policy.present_participant_ids, source) and
      MapSet.member?(policy.present_participant_ids, agent) and
      Effective.audio_route_permitted?(policy.effective, source, agent) and
      Effective.audio_route_permitted?(policy.effective, agent, source) and
      Snapshot.interval(policy, :audio_input, source) == signal.audio_input_interval and
      Snapshot.interval(policy, :audio_output, source) == signal.audio_output_interval
  end

  defp same_origin?(signal, origin) do
    is_reference(signal.allocation_generation) and
      signal.allocation_generation == origin.allocation_generation and
      signal.audio_input_interval == origin.audio_input_interval and
      signal.audio_output_interval == origin.audio_output_interval
  end

  defp intervals(signal),
    do: %{input: signal.audio_input_interval, output: signal.audio_output_interval}

  defp put_turn(state, turn) do
    binding = Map.put(state.speech_to_speech_capability, :activity_turn, turn)
    %{state | speech_to_speech_capability: binding}
  end

  def mode(%State{speech_to_speech_runtime: %SpeechToSpeechRuntime{provider: {_module, opts}}}) do
    Keyword.get(opts, :turn_control, "provider")
  end

  def mode(_state), do: "provider"
end
