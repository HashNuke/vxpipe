defmodule Vxpipe.CallEngine.RoomAuthority.EndCall do
  @moduledoc false

  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.RoomAuthority.{SpeechToSpeech, State, TextCapability}
  alias Vxpipe.CallEngine.Tool.Context

  @spec authorize(pid(), Context.t(), State.t()) :: :ok | {:error, Error.t()}
  def authorize(capability, %Context{} = context, %State{} = state) when is_pid(capability) do
    connection = Map.get(state.connections, context.connection_id)

    cond do
      TextCapability.current?(state, capability) and
        context.tenant_id == state.snapshot.tenant_id and
        context.room_id == state.snapshot.room_id and
        context.incarnation_id == state.snapshot.incarnation_id and
        connection != nil and
        connection.participant_id == context.source_participant_id and
        state.text_capability != nil and
          state.text_capability.participant_id == context.agent_participant_id ->
        :ok

      SpeechToSpeech.current?(state, capability) and
        context.tenant_id == state.snapshot.tenant_id and
        context.room_id == state.snapshot.room_id and
        context.incarnation_id == state.snapshot.incarnation_id and
        connection != nil and
        connection.participant_id == context.source_participant_id and
        state.speech_to_speech_capability != nil and
          state.speech_to_speech_capability.participant_id == context.agent_participant_id ->
        :ok

      true ->
        {:error,
         Error.new(
           :unauthorized_call_end,
           "The call cannot be ended by this tool invocation."
         )}
    end
  end
end
