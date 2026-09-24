defmodule Vxpipe.CallEngine.RoomAuthority.STSSourceCutover.NativeInput do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, State, STTAudioAdmission}

  def bind_audio_origin(connection_id, %State{} = state),
    do: STTAudioAdmission.synchronize(state, connection_id)

  def retire(connection_id, %State{} = state) do
    case Map.get(state.connections, connection_id) do
      %{speech_to_text: %{capability: capability}} = connection ->
        old_generation = generation(capability)
        state = ConnectionLifecycle.clear_speech_to_text_for_cutover(connection_id, state)
        current = Map.fetch!(state.connections, connection_id)
        start? = selected?(current.participant_id, state)
        demanded? = demanded?(state, current.participant_id)

        if start?, do: send(connection.pid, {:vxpipe_startup_speech, connection.room_monitor})

        update_cutover(state, old_generation, not (start? and demanded?))

      _no_stt ->
        update_cutover(state, nil, true)
    end
  catch
    :exit, _reason -> update_cutover(state, nil, false)
  end

  defp generation(capability) do
    case SpeechToText.input_binding(capability) do
      {:ok, %{allocation_generation: generation}} -> generation
      _not_ready -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp update_cutover(%State{source_cutover: %{}} = state, old_generation, ready?) do
    update_in(state.source_cutover, fn cutover ->
      %{cutover | old_stt_generation: old_generation, stt_ready?: ready?}
    end)
  end

  defp update_cutover(state, _old_generation, _ready?), do: state

  defp demanded?(%State{} = state, participant_id) do
    agent_id =
      case state.speech_to_speech_runtime do
        %{participant_id: agent} when is_binary(agent) -> agent
        _absent -> nil
      end

    case state.media_policy_authority do
      authority when is_pid(authority) ->
        case Authority.snapshot(authority) do
          %Snapshot{} = snapshot ->
            SpeechToTextDemand.required?(snapshot, participant_id, agent_id)

          _unavailable ->
            false
        end

      _absent ->
        false
    end
  catch
    :exit, _reason -> false
  end

  defp selected?(participant_id, %State{participant_transfer_runtime: %{plan: plan}}) do
    Enum.any?(Map.values(plan.participants), fn participant ->
      participant.participant_id == participant_id and
        participant.capabilities.speech_to_text != nil
    end)
  end

  defp selected?(_participant_id, _state), do: false
end
