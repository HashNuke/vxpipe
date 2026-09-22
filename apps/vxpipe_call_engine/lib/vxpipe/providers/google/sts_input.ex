defmodule Vxpipe.Providers.Google.STSInput do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Event
  alias Vxpipe.Providers.Google.STSResumption

  # The pinned profile has one final per audio caller, but no correlation ID.
  # Never turn several unfinished callers into an assumed FIFO association.
  def start(%{caller: %{ended?: false}} = state), do: {:ok, state}
  def start(%{caller: caller}) when not is_nil(caller), do: {:error, :ambiguous_input}

  def start(state) do
    turn = make_ref()

    result =
      if state.config.turn_control == "external",
        do: :ok,
        else: Event.emit(state.channel, :speech_started, turn_ref: turn)

    case result do
      :ok ->
        {:ok,
         STSResumption.begin_turn(%{
           state
           | caller: %{turn_ref: turn, ended?: false, final?: false, model_interrupted?: false},
             input_turn: turn,
             input_text: nil,
             input_ended?: false
         })}

      :discarded ->
        {:ok, state}

      _failure ->
        {:error, :session_failed}
    end
  end

  def finish(%{caller: nil} = state), do: {:ok, state}
  def finish(%{caller: %{ended?: true}} = state), do: {:ok, state}

  def finish(state) do
    caller = state.caller

    endpointing =
      if state.config.turn_control == "external", do: :external, else: :provider_semantic

    case Event.emit(state.channel, :turn_ended,
           turn_ref: caller.turn_ref,
           text: "",
           endpointing: endpointing
         ) do
      result when result in [:ok, :discarded] ->
        # An earlier interrupted model end is not completion of the response
        # that this genuine caller end now permits.
        ambiguous? = caller.model_interrupted? and not state.model_turn_complete?

        state = %{
          state
          | input_ended?: true,
            model_turn_complete?: false,
            interaction_status: :unknown,
            resumption_ambiguous?: state.resumption_ambiguous? or ambiguous?
        }

        {:ok, retire(state, %{caller | ended?: true})}

      _failure ->
        {:error, :session_failed}
    end
  end

  def interrupt_model(%{caller: %{ended?: false} = caller} = state),
    do: %{state | caller: %{caller | model_interrupted?: true}}

  def interrupt_model(state), do: state

  def transcript(%{caller: nil} = state, _text, _final?), do: {:ok, state}
  def transcript(%{caller: %{final?: true}} = state, _text, _final?), do: {:ok, state}

  def transcript(state, text, final?) do
    caller = state.caller

    case Event.emit(state.channel, :input_transcript,
           turn_ref: caller.turn_ref,
           text: text,
           final: final?
         ) do
      result when result in [:ok, :discarded] ->
        {:ok, retire(state, %{caller | final?: final?})}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp retire(state, %{ended?: true, final?: true}), do: %{state | caller: nil}
  defp retire(state, caller), do: %{state | caller: caller}
end
