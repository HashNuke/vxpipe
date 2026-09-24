defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.OriginRecovery do
  @moduledoc "Room-owned retirement and reopening of a selected STT activity origin."

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.STSIngress
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.{ActivityControl, Evidence}
  alias Vxpipe.CallEngine.RoomAuthority.STSSourceCutover
  alias Vxpipe.CallEngine.RoomAuthority.State

  def restore_ready(%State{speech_to_speech_recovery: %{track: track}} = state) do
    case state.speech_to_speech_capability do
      %{ingress: ingress} ->
        case STSIngress.prepare_track(ingress, track) do
          :ok ->
            case STSSourceCutover.active?(state) do
              true ->
                state = SpeechToSpeech.release(state)
                %{state | speech_to_speech_recovery: nil}

              false ->
                release_immediately(state)
            end

          _failed ->
            SpeechToSpeech.stop(state)
        end

      _not_ready ->
        SpeechToSpeech.stop(state)
    end
  end

  def restore_ready(%State{} = state), do: state

  def handle_activity_origin_changed(%State{} = state, capability, revision)
      when is_pid(capability) and is_integer(revision) do
    with true <- SpeechToSpeech.current?(state, capability),
         mode when mode in ["external", "hybrid"] <- ActivityControl.mode(state),
         %{connection_id: connection_id, connection: connection, ingress: old_ingress} <-
           state.speech_to_speech_capability,
         {:ok, %{track: track}} <- STSIngress.input_contract(old_ingress),
         %Snapshot{revision: current_revision} <- Evidence.policy_snapshot(state),
         true <- current_revision >= revision do
      state
      |> SpeechToSpeech.hold(:policy)
      |> SpeechToSpeech.stop()
      |> Map.put(:speech_to_speech_recovery, %{
        connection_id: connection_id,
        connection: connection,
        track: track
      })
      |> defer_recovery_until_source_ready()
    else
      _stale -> state
    end
  end

  def handle_activity_origin_changed(%State{} = state, _capability, _revision), do: state

  def recover(%State{speech_to_speech_recovery: nil} = state), do: state

  def recover(%State{speech_to_speech_recovery: recovery} = state) do
    with %{pid: owner, speech_to_text: %{capability: stt}} = connection <-
           Map.get(state.connections, recovery.connection_id),
         true <- owner == recovery.connection and connection.admission == :main,
         false <- MapSet.member?(state.held_participant_ids, connection.participant_id),
         {:ok, %{activity_origin: %{agent_id: agent} = origin, identity: identity}} <-
           SpeechToText.input_binding(stt),
         true <- agent == state.speech_to_speech_runtime.participant_id,
         true <- identity == Map.take(connection.attach_command, Map.keys(identity)),
         %Snapshot{} = policy <- Evidence.policy_snapshot(state),
         true <- recoverable_origin?(policy, connection.participant_id, agent, origin) do
      SpeechToSpeech.maybe_start(state, connection)
    else
      _not_ready -> state
    end
  catch
    :exit, _reason -> state
  end

  defp recoverable_origin?(policy, source, agent, origin) do
    Snapshot.valid?(policy) and
      MapSet.member?(policy.present_participant_ids, source) and
      MapSet.member?(policy.present_participant_ids, agent) and
      Effective.audio_route_permitted?(policy.effective, source, agent) and
      Effective.audio_route_permitted?(policy.effective, agent, source) and
      origin.audio_input_interval == Snapshot.interval(policy, :audio_input, source) and
      origin.audio_output_interval == Snapshot.interval(policy, :audio_output, source)
  end

  defp defer_recovery_until_source_ready(%State{} = state) do
    if STSSourceCutover.active?(state),
      do: put_in(state.source_cutover.sts_ready?, false),
      else: recover(state)
  end

  defp release_immediately(state) do
    case SpeechToSpeech.release(state) do
      %{speech_to_speech_capability: %{input_epoch: epoch}} = released
      when is_reference(epoch) ->
        %{released | speech_to_speech_recovery: nil}

      _failed ->
        SpeechToSpeech.stop(state)
    end
  end
end
