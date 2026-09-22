defmodule Vxpipe.Providers.Google.STSOutput do
  @moduledoc "Google STS bounded output assembly and completion through engine output credit."

  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  @maximum_pending_audio 16
  @maximum_text_bytes 65_536

  def buffer_transcript(%{audio_fenced?: true} = state, _text), do: {:ok, state}
  def buffer_transcript(%{generation_pending_done?: true} = state, _text), do: {:ok, state}

  def buffer_transcript(%{output: %{generation_done?: true}} = state, _text),
    do: {:ok, state}

  def buffer_transcript(state, text) do
    accumulated = (state.output_text || "") <> text

    if byte_size(accumulated) <= @maximum_text_bytes,
      do: publish_transcript(%{state | output_text: accumulated}),
      else: {:error, :session_failed}
  end

  def publish_transcript(%{output: nil} = state), do: {:ok, state}
  def publish_transcript(%{output_text: nil} = state), do: {:ok, state}

  def publish_transcript(state) do
    case Event.emit(state.channel, :output_transcript,
           turn_ref: state.output.turn_ref,
           text: state.output_text
         ) do
      result when result in [:ok, :discarded] -> {:ok, state}
      _failure -> {:error, :session_failed}
    end
  end

  def buffer_audio(state, pcm) do
    case state.output do
      %{queue: queue} = output when length(queue) < @maximum_pending_audio ->
        {:ok, %{state | output: %{output | queue: queue ++ [pcm]}}}

      %{queue: _full} ->
        {:error, :session_failed}

      nil ->
        if length(state.audio_buffer) < @maximum_pending_audio do
          {:ok, %{state | audio_buffer: state.audio_buffer ++ [pcm]}}
        else
          {:error, :session_failed}
        end
    end
  end

  def open_output(state, turn_ref, output_ref) do
    %{
      state
      | output: %{
          turn_ref: turn_ref,
          output_ref: output_ref,
          queue: state.audio_buffer,
          awaiting: nil,
          generation_done?: state.generation_pending_done?,
          interrupted?: false,
          completed_emitted?: false
        },
        audio_buffer: [],
        generation_pending_done?: false
    }
  end

  def mark_generation_done(%{output: nil} = state),
    do: %{state | generation_pending_done?: true}

  def mark_generation_done(state),
    do: %{state | output: %{state.output | generation_done?: true}}

  def drain_output(
        %{output: %{queue: [], awaiting: nil, generation_done?: true} = output} = state
      ) do
    case Event.emit(state.channel, :output_completed,
           turn_ref: output.turn_ref,
           request_ref: output.output_ref
         ) do
      :ok -> {:ok, %{state | output: %{output | awaiting: :completed, completed_emitted?: true}}}
      _failure -> {:error, :session_failed}
    end
  end

  def drain_output(%{output: %{interrupted?: true}} = state), do: {:ok, state}

  def drain_output(%{output: %{queue: [pcm | rest], awaiting: nil} = output} = state) do
    case Channel.submit(state.channel, output.output_ref, pcm) do
      {:ok, credit} ->
        {:ok, %{state | output: %{output | queue: rest, awaiting: credit}}}

      _failure ->
        {:error, :session_failed}
    end
  end

  def drain_output(state), do: {:ok, state}
end
