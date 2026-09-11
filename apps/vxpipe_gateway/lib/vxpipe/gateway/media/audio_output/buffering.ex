defmodule Vxpipe.Gateway.Media.AudioOutput.Buffering do
  @moduledoc false

  alias Vxpipe.Gateway.Media.{AudioOutput.State, PlaybackFrame}

  @frame_bytes 1_920
  @frame_samples 960

  @spec accept(binary(), State.t()) ::
          {:accepted, State.t()} | {:backpressure, binary(), State.t()}
  def accept(pcm, %State{} = state) when is_binary(pcm) do
    frame_count = div(byte_size(pcm), @frame_bytes)
    accepted_count = min(frame_count, available_capacity(state))
    accepted_bytes = accepted_count * @frame_bytes
    <<accepted::binary-size(accepted_bytes), pending::binary>> = pcm
    state = enqueue(accepted, accepted_count, state)

    if div(byte_size(pending), @frame_bytes) == 0 do
      {:accepted, %{state | remainder: pending}}
    else
      {:backpressure, pending, state}
    end
  end

  @spec finish(State.t()) :: {:ok, State.t()} | {:backpressure, State.t()}
  def finish(%State{remainder: <<>>} = state), do: {:ok, mark_finished(state)}

  def finish(%State{} = state) do
    if available_capacity(state) > 0 do
      padding = :binary.copy(<<0>>, @frame_bytes - byte_size(state.remainder))
      state = enqueue(state.remainder <> padding, 1, %{state | remainder: <<>>})
      {:ok, mark_finished(state)}
    else
      {:backpressure, state}
    end
  end

  defp enqueue(<<>>, 0, state), do: state

  defp enqueue(pcm, count, state) do
    {queue, next_sequence_number} =
      pcm
      |> split([])
      |> Enum.reduce({state.queue, state.next_sequence_number}, fn payload, {queue, sequence} ->
        frame = %PlaybackFrame{
          sequence_number: sequence,
          timestamp: sequence * @frame_samples,
          sample_rate: 48_000,
          payload: payload
        }

        {:queue.in(frame, queue), sequence + 1}
      end)

    current = %{state.current | frame_count: state.current.frame_count + count}
    %{state | current: current, next_sequence_number: next_sequence_number, queue: queue}
  end

  defp split(<<>>, frames), do: Enum.reverse(frames)

  defp split(<<frame::binary-size(@frame_bytes), rest::binary>>, frames) do
    split(rest, [frame | frames])
  end

  defp available_capacity(state) do
    in_flight = if is_nil(state.in_flight), do: 0, else: 1
    max(state.maximum_frames - :queue.len(state.queue) - in_flight, 0)
  end

  defp mark_finished(state), do: %{state | current: %{state.current | finished?: true}}
end
