defmodule Vxpipe.Providers.Google.STSOutput do
  @moduledoc "Google STS PCM buffering and generation completion through engine output credit."

  alias Vxpipe.CallEngine.Speech.{Channel, Event}

  @maximum_pending_audio 16

  def buffer_audio(state, pcm) do
    case state.output do
      %{queue: queue} = output ->
        {:ok, %{state | output: %{output | queue: queue ++ [pcm]}}}

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
