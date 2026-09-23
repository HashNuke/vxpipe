defmodule Vxpipe.CallEngine.RoomAuthority.STTAudioAdmission do
  @moduledoc "Room-owned binding of the selected source recognizer's current audio origin."

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.RoomAuthority.State

  @spec synchronize(State.t(), String.t()) :: :ok | {:error, term()}
  def synchronize(%State{} = state, connection_id) do
    case selected_source(state, connection_id) do
      {:ok, %{speech_to_text: %{capability: capability, ingress: ingress}} = connection, agent} ->
        bind_current(state, connection_id, connection, capability, ingress, agent)

      _not_selected ->
        :ok
    end
  end

  defp selected_source(
         %State{
           speech_to_speech_runtime: %{participant_id: agent},
           participant_transfer_runtime: %{plan: plan}
         } = state,
         connection_id
       ) do
    with {:ok, caller} <- Map.fetch(plan.participants, plan.entry_caller),
         %{role: :human, admission: :main, participant_id: source} = connection <-
           Map.get(state.connections, connection_id),
         true <- source == caller.participant_id and is_binary(agent) do
      {:ok, connection, agent}
    else
      _not_selected -> :error
    end
  end

  defp selected_source(_state, _connection_id), do: :error

  defp bind_current(state, connection_id, connection, capability, ingress, agent) do
    expected_identity = %{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: connection.participant_id,
      connection_id: connection_id
    }

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
