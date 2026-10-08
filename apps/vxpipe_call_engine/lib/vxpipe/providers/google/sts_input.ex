defmodule Vxpipe.Providers.Google.STSInput do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Event
  alias Vxpipe.Providers.Google.STSResumption

  def context_command({:audio, pcm}) when is_binary(pcm), do: {:ok, {:push_audio, pcm}}

  def context_command({:text, reference, text})
      when is_reference(reference) and is_binary(text),
      do: {:ok, {:push_text, reference, text}}

  def context_command({:opening, reference, opening}) when is_reference(reference),
    do: {:ok, {:begin_opening, reference, opening}}

  def context_command({:activity, boundary}) when boundary in [:started, :ended],
    do: {:ok, {:input_activity, boundary}}

  def context_command(_operation), do: {:error, :unsupported_operation}

  def open_text_turn(state) do
    case Event.emit(state.channel, :turn_ended,
           turn_ref: state.input_turn,
           text: state.input_text,
           endpointing: input_endpointing(state)
         ) do
      :ok -> {:ok, %{state | input_ended?: true}}
      :discarded -> {:ok, %{state | input_ended?: true}}
      _failure -> {:error, :session_failed}
    end
  end

  def activity_boundary(:started, state), do: start(state)
  def activity_boundary(:ended, state), do: finish(state)

  defp input_endpointing(%{config: %{turn_control: "external"}}), do: :external
  defp input_endpointing(_state), do: :provider_semantic

  def bind_context(%{interaction_context: nil}, context, {:activity, :ended})
      when is_reference(context),
      do: {:error, :busy}

  def bind_context(%{interaction_context: nil} = state, context, _operation)
      when is_reference(context),
      do: {:ok, %{state | interaction_context: context}}

  def bind_context(%{interaction_context: context} = state, context, _operation)
      when is_reference(context),
      do: {:ok, state}

  def bind_context(%{interaction_context: previous} = state, context, operation)
      when is_reference(previous) and is_reference(context) do
    if operation != {:activity, :ended} and not state.resuming? and
         STSResumption.quiescent?(state) do
      {:ok, %{state | interaction_context: context}}
    else
      {:error, :busy}
    end
  end

  def bind_context(_state, _context, _operation), do: {:error, :busy}

  # The pinned profile has one final per audio caller, but no correlation ID, and some caller
  # activity (noise, a cut-off word) never receives a final. Failing the session there ended
  # live calls. Instead the earlier caller is settled without text, and the next final is
  # settled without text too because it may be that earlier caller's late final. Nothing is
  # attributed by guesswork; only one transcript is lost and the conversation continues.
  def start(%{caller: %{ended?: false}} = state), do: {:ok, state}

  def start(%{caller: caller} = state) when not is_nil(caller) do
    case settle_without_text(state, caller) do
      {:ok, state} ->
        with {:ok, state} <- start(%{state | caller: nil, resumption_ambiguous?: true}),
             do: {:ok, discard_next_final(state)}

      error ->
        error
    end
  end

  def start(state) do
    turn = make_ref()
    audio_fenced? = state.audio_fenced? and not state.model_turn_complete?

    result =
      if state.config.turn_control == "external",
        do: :ok,
        else: Event.emit(state.channel, :speech_started, turn_ref: turn)

    case result do
      :ok ->
        {:ok,
         %{
           STSResumption.begin_turn(state)
           | caller: %{
               turn_ref: turn,
               ended?: false,
               final?: false,
               model_interrupted?: false,
               discard_final?: false
             },
             input_turn: turn,
             input_text: nil,
             input_ended?: false,
             audio_fenced?: audio_fenced?
         }}

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
            audio_fenced?: false,
            resumption_ambiguous?: state.resumption_ambiguous? or ambiguous?
        }

        state = if ambiguous?, do: %{state | clean_exchange?: false}, else: state

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

  # This caller's first final may belong to the caller settled before it; settle it empty.
  def transcript(%{caller: %{discard_final?: true}} = state, _text, false), do: {:ok, state}

  def transcript(%{caller: %{discard_final?: true} = caller} = state, _text, true) do
    case settle_without_text(state, caller) do
      {:ok, state} -> {:ok, retire(state, %{caller | final?: true, discard_final?: false})}
      error -> error
    end
  end

  def transcript(state, text, final?) do
    caller = state.caller

    case Event.emit(state.channel, :input_transcript,
           turn_ref: caller.turn_ref,
           text: text,
           final: final?
         ) do
      result when result in [:ok, :discarded] ->
        state = if final?, do: STSResumption.observed_caller_final(state), else: state
        {:ok, retire(state, %{caller | final?: final?})}

      _failure ->
        {:error, :session_failed}
    end
  end

  defp settle_without_text(state, caller) do
    case Event.emit(state.channel, :input_transcript,
           turn_ref: caller.turn_ref,
           text: "",
           final: true
         ) do
      result when result in [:ok, :discarded] -> {:ok, STSResumption.observed_caller_final(state)}
      _failure -> {:error, :session_failed}
    end
  end

  defp discard_next_final(%{caller: caller} = state) when is_map(caller),
    do: %{state | caller: %{caller | discard_final?: true}, clean_exchange?: false}

  defp discard_next_final(state), do: state

  defp retire(state, %{ended?: true, final?: true}), do: %{state | caller: nil}
  defp retire(state, caller), do: %{state | caller: caller}
end
