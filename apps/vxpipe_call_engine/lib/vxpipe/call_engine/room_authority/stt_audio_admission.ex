defmodule Vxpipe.CallEngine.RoomAuthority.STTAudioAdmission do
  @moduledoc "Room-owned binding of the selected source recognizer's current audio origin."

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence
  alias Vxpipe.CallEngine.RoomAuthority.State

  @spec synchronize(State.t(), String.t()) :: :ok | {:error, term()}
  def synchronize(%State{} = state, connection_id) do
    case Evidence.agent_connection(state) do
      {^connection_id,
       %{speech_to_text: %{capability: capability, ingress: ingress}} = connection} ->
        bind_current(state, connection_id, connection, capability, ingress)

      _not_selected ->
        :ok
    end
  end

  defp bind_current(state, connection_id, connection, capability, ingress) do
    expected_identity = %{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: connection.participant_id,
      connection_id: connection_id
    }

    agent = state.speech_to_speech_capability.participant_id

    origin =
      case SpeechToText.input_binding(capability) do
        {:ok, %{identity: ^expected_identity, audio_origin: %{agent_id: ^agent} = origin}} ->
          origin

        _unready_or_changed ->
          nil
      end

    Ingress.bind_audio_origin(ingress, origin)
  end
end
