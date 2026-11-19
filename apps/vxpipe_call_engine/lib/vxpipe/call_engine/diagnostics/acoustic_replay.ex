defmodule Vxpipe.CallEngine.Diagnostics.AcousticReplay do
  @moduledoc "Offline replay of timestamped 16 kHz PCM windows through an explicitly supplied Silero model."
  alias Vxpipe.CallEngine.Diagnostics.AcousticObserver
  alias Vxpipe.CallEngine.Speech.ActivityBoundary
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
      frame_count: 0,
      inference_epoch: 0,
      epoch_origin: nil,
      segment_packets: [],
      progress: nil
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
           frame_count: state.frame_count,
           segment_evidence: %{
             clock_id: clock_id,
             source_epoch: source_epoch,
             packets: Enum.reverse(state.segment_packets) ++ [state.progress]
           }
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
      state = segment_evidence(state, observer, events, notices, metadata, processed)

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

  defp segment_evidence(state, observer, events, notices, metadata, processed) do
    epoch = if notices == [], do: state.inference_epoch, else: state.inference_epoch + 1

    origin =
      if notices == [],
        do: state.epoch_origin || metadata.sample_timestamp,
        else: metadata.sample_timestamp

    packets =
      if notices == [] do
        state.segment_packets
      else
        [
          {:reset, epoch, hd(notices), metadata.received_offset_us},
          state.progress
          | state.segment_packets
        ]
      end

    packets =
      Enum.reduce(events, packets, fn
        {kind, position}, acc ->
          reason = if kind == :speech_started and position.sample == origin, do: :partial_start

          [
            {:acoustic_boundary, epoch, kind, position.sample, position.offset_us,
             position.confirmed_offset_us, position.uncertainty_us, reason}
            | acc
          ]

        {:unmapped_boundary, kind, sample, reason}, acc ->
          [{:acoustic_boundary, epoch, kind, sample, nil, processed, nil, reason} | acc]
      end)

    %{
      state
      | inference_epoch: epoch,
        epoch_origin: origin,
        segment_packets: packets,
        progress:
          {:acoustic_progress, epoch, origin,
           ActivityBoundary.finalized_samples(observer.boundary)}
    }
  end

  defp contiguous?(nil, _frame), do: true

  defp contiguous?(previous, frame),
    do:
      frame.sequence == previous.sequence + 1 and
        frame.sample_timestamp == previous.sample_timestamp + previous.sample_count and
        frame.source_epoch == previous.source_epoch
end
