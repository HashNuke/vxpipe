defmodule Vxpipe.Providers.Google.STSResponseDelivery do
  @moduledoc """
  Exact Google model-response delivery through one credited engine output slot.

  The pure response owner keeps independent wire and playback obligations; this
  adapter emits their bounded channel events and submits only credited PCM.
  """

  alias Vxpipe.CallEngine.Speech.{Channel, Event}
  alias Vxpipe.Providers.Google.{STSInput, STSResponses}

  def transcript(%{interaction_context: nil} = state, _text), do: {:ok, state}

  def transcript(state, text) do
    with {:ok, owner, _response} <-
           STSResponses.ensure_wire(state.responses, state.interaction_context),
         {:ok, owner} <- STSResponses.append_text(owner, text) do
      state = %{state | responses: owner}
      publish_text(state, owner.wire)
    else
      _failure -> {:error, :session_failed}
    end
  end

  def audio(%{interaction_context: nil} = state, _pcm), do: {:ok, state}

  def audio(state, pcm) do
    with {:ok, owner, _response} <-
           STSResponses.ensure_wire(state.responses, state.interaction_context),
         {:ok, owner, announcement} <- STSResponses.append_audio(owner, pcm),
         :ok <- announce(state.channel, announcement) do
      drain(%{state | responses: owner})
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _failure -> {:error, :session_failed}
    end
  end

  def tool_turn(state) do
    case STSResponses.ensure_wire(state.responses, state.interaction_context) do
      {:ok, owner, response} -> {:ok, %{state | responses: owner}, response.ref}
      _failure -> {:error, :session_failed}
    end
  end

  def generation_end(state) do
    with {:ok, owner} <- STSResponses.generation_end(state.responses),
         do: drain(%{state | responses: owner})
  end

  def model_end(state) do
    case STSResponses.model_end(state.responses) do
      {:ok, owner} -> {:ok, %{state | responses: owner}}
      _failure -> {:error, :session_failed}
    end
  end

  def interrupted(state) do
    state = STSInput.interrupt_model(state)

    case state.responses.wire do
      nil ->
        {:ok, state}

      turn ->
        with :ok <- Event.emit(state.channel, :interrupted, turn_ref: turn),
             {:ok, owner} <- STSResponses.discard(state.responses, turn),
             {:ok, owner} <- STSResponses.model_end(owner) do
          drain(%{state | responses: owner})
        else
          _failure -> {:error, :session_failed}
        end
    end
  end

  def interrupt(
        %{config: %{turn_control: "provider"}, caller: %{ended?: false}} = state,
        turn
      )
      when state.responses.wire == turn do
    # Real provider VAD has already observed the caller. Fence local delivery
    # without inventing a cancellation command; retain wire ownership until
    # Google's interrupted/model boundary arrives, dropping the old tail.
    discard(state, turn)
  end

  def interrupt(state, turn) when state.responses.wire == turn,
    do: {:error, :unsupported_interrupt}

  def interrupt(state, turn), do: discard(state, turn)

  def grant(state, turn, output) do
    with {:ok, owner} <- STSResponses.grant(state.responses, turn, output),
         state = %{state | responses: owner},
         {:ok, state} <- publish_text(state, turn) do
      drain(state)
    else
      _failure -> {:error, :session_failed}
    end
  end

  def credit(state, output, credit) do
    case STSResponses.ack_credit(state.responses, output, credit) do
      {:ok, owner} -> drain(%{state | responses: owner})
      {:error, :stale_credit} -> {:ok, state}
    end
  end

  def settle(state, turn, output) do
    case STSResponses.settle(state.responses, turn, output) do
      {:ok, owner} -> {:ok, %{state | responses: owner}}
      {:error, _reason} -> {:ok, state}
    end
  end

  def discard(state, turn) do
    case STSResponses.discard(state.responses, turn) do
      {:ok, owner} -> drain(%{state | responses: owner})
      {:error, :stale_response} -> {:ok, state}
    end
  end

  def drain(state) do
    case STSResponses.fetch(state.responses, state.responses.active) do
      {:ok, %{queue: [pcm | _], awaiting: nil, output_ref: output, ref: turn}} ->
        with {:ok, credit} <- Channel.submit(state.channel, output, pcm),
             {:ok, owner} <- STSResponses.sent_audio(state.responses, turn, output, credit) do
          {:ok, %{state | responses: owner}}
        else
          _failure -> {:error, :session_failed}
        end

      {:ok,
       %{
         queue: [],
         awaiting: nil,
         generation_done?: true,
         completed?: false,
         output_ref: output,
         ref: turn
       }} ->
        with :ok <-
               Event.emit(state.channel, :output_completed, turn_ref: turn, request_ref: output),
             {:ok, owner} <- STSResponses.completed(state.responses, turn, output) do
          {:ok, %{state | responses: owner}}
        else
          _failure -> {:error, :session_failed}
        end

      _other ->
        {:ok, state}
    end
  end

  defp announce(_channel, nil), do: :ok

  defp announce(channel, %{ref: turn, index: index, context: context}) do
    Event.emit(channel, :response_started,
      turn_ref: turn,
      response_index: index,
      response_context: context
    )
  end

  defp publish_text(state, turn) do
    case STSResponses.fetch(state.responses, turn) do
      {:ok, %{output_ref: output, text: text}} when is_reference(output) and is_binary(text) ->
        case Event.emit(state.channel, :output_transcript, turn_ref: turn, text: text) do
          :ok -> {:ok, state}
          _failure -> {:error, :session_failed}
        end

      _other ->
        {:ok, state}
    end
  end
end
