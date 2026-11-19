defmodule Vxpipe.CallEngine.Diagnostics.AcousticReplay do
  @moduledoc "Offline replay of timestamped 16 kHz PCM windows through an explicitly supplied Silero model."
  alias Vxpipe.CallEngine.Diagnostics.AcousticObserver
  alias Vxpipe.CallEngine.Speech.Silero
  alias Vxpipe.CallEngine.Speech.Silero.Model

  def run(%Model{} = model, frames, clock_id, source_epoch)
      when is_list(frames) and length(frames) in 1..10_000 do
    initial = %{
      observer: AcousticObserver.new(clock_id, source_epoch),
      stream: Silero.new(),
      previous: nil,
      previous_pcm: nil,
      events: [],
      notices: [],
      frame_count: 0
    }

    frames
    |> Enum.reduce_while({:ok, initial}, fn frame, {:ok, state} ->
      case frame(model, state, frame) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, state} ->
        {:ok,
         %{
           events: Enum.reverse(state.events),
           notices: Enum.uniq(state.notices),
           frame_count: state.frame_count
         }}

      error ->
        error
    end
  end

  def run(_model, _frames, _clock_id, _source_epoch), do: {:error, :invalid_replay_audio}

  defp frame(
         model,
         state,
         %{
           pcm: pcm,
           sample_count: 512,
           processed_offset_us: processed,
           received_offset_us: received,
           sample_timestamp: timestamp,
           sequence: sequence,
           source_epoch: source
         } = frame
       )
       when is_binary(pcm) and byte_size(pcm) == 1_024 and map_size(frame) == 7 and
              is_integer(processed) and is_integer(received) and processed >= received and
              processed <= 604_800_000_000 and is_integer(timestamp) and timestamp >= 0 and
              is_integer(sequence) and sequence >= 0 and is_binary(source) do
    metadata = Map.drop(frame, [:pcm, :processed_offset_us])

    cond do
      metadata == state.previous and pcm == state.previous_pcm ->
        {:ok, state}

      state.previous != nil and sequence == state.previous.sequence ->
        {:error, :conflicting_frame}

      true ->
        infer(model, state, metadata, pcm, processed)
    end
  end

  defp frame(_model, _state, _frame), do: {:error, :invalid_replay_audio}

  defp infer(model, state, metadata, pcm, processed) do
    stream = if contiguous?(state.previous, metadata), do: state.stream, else: Silero.new()

    with {:ok, stream, [probability]} <- Silero.push(stream, model, pcm),
         {:ok, observer, events, notices} <-
           AcousticObserver.observe(state.observer, metadata, probability, processed) do
      {:ok,
       %{
         state
         | stream: stream,
           observer: observer,
           previous: metadata,
           previous_pcm: :binary.copy(pcm),
           events: Enum.reverse(events, state.events),
           notices: notices ++ state.notices,
           frame_count: state.frame_count + 1
       }}
    end
  end

  defp contiguous?(nil, _frame), do: true

  defp contiguous?(previous, frame),
    do:
      frame.sequence == previous.sequence + 1 and
        frame.sample_timestamp == previous.sample_timestamp + previous.sample_count and
        frame.source_epoch == previous.source_epoch
end
