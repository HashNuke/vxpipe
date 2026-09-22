defmodule Vxpipe.CallEngine.RoomAuthority.UsageSource do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.RoomAuthority.{State, TextCapability}

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    HumanPreparation,
    Pending,
    Preparation
  }

  @type source :: %{participant_id: String.t(), activation_id: String.t() | nil}

  @spec resolve(State.t(), pid()) :: {:ok, source()} | {:error, :unauthorized}
  def resolve(%State{} = state, capability) when is_pid(capability) do
    with :error <- active_text_source(state, capability),
         :error <- pending_text_source(state, capability),
         :error <- connection_speech_source(state, capability),
         :error <- active_speech_source(state, capability),
         :error <- pending_speech_source(state.pending_participant_transfer, capability) do
      {:error, :unauthorized}
    end
  end

  defp active_text_source(state, capability) do
    if TextCapability.current?(state, capability) do
      source(state.text_capability)
    else
      :error
    end
  end

  defp pending_text_source(state, capability) do
    case Map.fetch(state.pending_agent_teardowns, capability) do
      {:ok, pending} ->
        activation_id =
          Recorder.participant_activation(state.archive_recorder, pending.participant_id)

        {:ok, %{activation_id: activation_id, participant_id: pending.participant_id}}

      :error ->
        :error
    end
  end

  defp connection_speech_source(state, capability) do
    Enum.find_value(state.connections, :error, fn {_connection_id, connection} ->
      case Map.get(connection, :speech_to_text) do
        %{capability: ^capability} ->
          activation_id =
            Recorder.participant_activation(state.archive_recorder, connection.participant_id)

          {:ok,
           %{
             activation_id: activation_id,
             participant_id: connection.participant_id
           }}

        _unbound ->
          false
      end
    end)
  end

  defp active_speech_source(%{text_to_speech_capability: nil} = state, capability) do
    active_sts_source(state, capability)
  end

  defp active_speech_source(state, capability) do
    case speech_source(state.text_to_speech_capability, capability) do
      {:ok, _source} = ok -> ok
      :error -> active_sts_source(state, capability)
    end
  end

  defp active_sts_source(%{speech_to_speech_capability: nil}, _capability), do: :error

  defp active_sts_source(state, capability) do
    speech_source(state.speech_to_speech_capability, capability)
  end

  defp pending_speech_source(
         %Pending{preparation: %HumanPreparation{text_to_speech: text_to_speech}},
         capability
       ) do
    speech_source(text_to_speech, capability)
  end

  defp pending_speech_source(
         %Pending{preparation: %Preparation{text_to_speech: text_to_speech}},
         capability
       ) do
    speech_source(text_to_speech, capability)
  end

  defp pending_speech_source(_pending, _capability), do: :error

  defp speech_source(nil, _capability), do: :error

  defp speech_source(%{pid: capability} = text_to_speech, capability) do
    source(text_to_speech)
  end

  defp speech_source(_text_to_speech, _capability), do: :error

  defp source(capability) do
    {:ok,
     %{
       activation_id: Map.get(capability, :activation_id),
       participant_id: capability.participant_id
     }}
  end
end
