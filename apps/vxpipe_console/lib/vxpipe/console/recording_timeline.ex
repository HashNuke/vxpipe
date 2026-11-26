defmodule Vxpipe.Console.RecordingTimeline do
  @moduledoc """
  Shared per-track timeline math for virtual recording files.

  Both the single-track WAV reader and the multi-track Matroska reader align
  room-clock gaps to silence without duplicating segment logic.
  """

  @type segment :: %{
          required(:kind) => :object | :silence,
          required(:first) => non_neg_integer(),
          required(:length) => pos_integer(),
          required(:object_first) => non_neg_integer() | nil
        }

  @spec frame_bytes(map()) :: {:ok, pos_integer()} | {:error, atom()}
  def frame_bytes(%{sample_format: :s16le, channels: channels})
      when is_integer(channels) and channels > 0 and channels <= 8 do
    {:ok, channels * 2}
  end

  def frame_bytes(_), do: {:error, :unsupported_recording_layout}

  @spec local_timeline(map()) :: {:ok, pos_integer()} | {:error, atom()}
  def local_timeline(%{
        started_offset_samples: started,
        ended_offset_samples: ended,
        sample_count: sample_count
      })
      when is_integer(started) and started >= 0 and is_integer(ended) and ended > started and
             is_integer(sample_count) and sample_count > 0 do
    {:ok, ended - started}
  end

  def local_timeline(_), do: {:error, :unsupported_recording_layout}

  @spec local_segments(map(), pos_integer()) ::
          {:ok, [segment()], non_neg_integer(), non_neg_integer()} | {:error, atom()}
  def local_segments(source, frame_bytes) when is_integer(frame_bytes) and frame_bytes > 0 do
    with {:ok, timeline_samples} <- local_timeline(source),
         {:ok, segments, raw_samples, gap_samples} <-
           build_segments(
             source.gaps,
             source.started_offset_samples,
             source.ended_offset_samples,
             frame_bytes
           ),
         true <- raw_samples == source.sample_count,
         true <- gap_samples == timeline_samples - source.sample_count do
      {:ok, segments, raw_samples, gap_samples}
    else
      _invalid -> {:error, :unsupported_recording_layout}
    end
  end

  @spec global_segments(map(), non_neg_integer(), pos_integer(), pos_integer()) ::
          {:ok, [segment()]} | {:error, atom()}
  def global_segments(source, zero, timeline_samples, frame_bytes)
      when is_integer(zero) and zero >= 0 and is_integer(timeline_samples) and
             timeline_samples > 0 and
             is_integer(frame_bytes) and frame_bytes > 0 do
    with {:ok, local_segments, _raw, _gaps} <- local_segments(source, frame_bytes),
         true <- source.started_offset_samples >= zero,
         true <- source.ended_offset_samples - zero <= timeline_samples do
      leading_samples = source.started_offset_samples - zero
      trailing_samples = timeline_samples - (source.ended_offset_samples - zero)
      leading_bytes = leading_samples * frame_bytes
      trailing_bytes = trailing_samples * frame_bytes

      shifted =
        Enum.map(local_segments, fn segment ->
          %{segment | first: segment.first + leading_bytes}
        end)

      timeline_bytes = timeline_samples * frame_bytes

      segments =
        maybe_prepend_silence(shifted, leading_bytes)
        |> maybe_append_silence(timeline_bytes, trailing_bytes)

      if valid_coverage?(segments, timeline_bytes),
        do: {:ok, segments},
        else: {:error, :unsupported_recording_layout}
    else
      _invalid -> {:error, :unsupported_recording_layout}
    end
  end

  defp maybe_prepend_silence(segments, 0), do: segments

  defp maybe_prepend_silence(segments, leading_bytes) do
    [%{kind: :silence, first: 0, length: leading_bytes, object_first: nil} | segments]
  end

  defp maybe_append_silence(segments, _timeline_bytes, 0), do: segments

  defp maybe_append_silence(segments, timeline_bytes, trailing_bytes) do
    segments ++
      [
        %{
          kind: :silence,
          first: timeline_bytes - trailing_bytes,
          length: trailing_bytes,
          object_first: nil
        }
      ]
  end

  defp valid_coverage?(segments, timeline_bytes) do
    {cursor, covered?} =
      Enum.reduce_while(segments, {0, true}, fn segment, {cursor, _} ->
        if segment.first == cursor and segment.length > 0,
          do: {:cont, {cursor + segment.length, true}},
          else: {:halt, {cursor, false}}
      end)

    covered? and cursor == timeline_bytes
  end

  defp build_segments(gaps, started, ended, frame_bytes) when is_list(gaps) do
    initial = {:ok, [], started, 0, 0, 0}

    with {:ok, reversed, cursor, raw_samples, gap_samples, virtual_bytes} <-
           Enum.reduce_while(gaps, initial, fn gap, state ->
             case add_gap(gap, state, ended, frame_bytes) do
               {:ok, _, _, _, _, _} = next -> {:cont, next}
               {:error, _reason} = error -> {:halt, error}
             end
           end),
         true <- cursor <= ended do
      data_samples = ended - cursor

      {reversed, raw_samples, _virtual_bytes} =
        add_object_segment(reversed, raw_samples, virtual_bytes, data_samples, frame_bytes)

      {:ok, Enum.reverse(reversed), raw_samples, gap_samples}
    else
      _invalid -> {:error, :unsupported_recording_layout}
    end
  end

  defp build_segments(_gaps, _started, _ended, _frame_bytes),
    do: {:error, :unsupported_recording_layout}

  defp add_gap(
         %{"offset_samples" => offset, "sample_count" => count} = gap,
         {:ok, reversed, cursor, raw_samples, gap_samples, virtual_bytes},
         ended,
         frame_bytes
       )
       when map_size(gap) == 2 and is_integer(offset) and is_integer(count) and count > 0 and
              offset >= cursor and offset + count <= ended do
    data_samples = offset - cursor

    {reversed, raw_samples, virtual_bytes} =
      add_object_segment(reversed, raw_samples, virtual_bytes, data_samples, frame_bytes)

    silence_bytes = count * frame_bytes

    {:ok, [segment(:silence, virtual_bytes, silence_bytes, nil) | reversed], offset + count,
     raw_samples, gap_samples + count, virtual_bytes + silence_bytes}
  end

  defp add_gap(_gap, _state, _ended, _frame_bytes),
    do: {:error, :unsupported_recording_layout}

  defp add_object_segment(reversed, raw_samples, virtual_bytes, 0, _frame_bytes),
    do: {reversed, raw_samples, virtual_bytes}

  defp add_object_segment(reversed, raw_samples, virtual_bytes, sample_count, frame_bytes) do
    length = sample_count * frame_bytes
    object_first = raw_samples * frame_bytes

    {[
       segment(:object, virtual_bytes, length, object_first) | reversed
     ], raw_samples + sample_count, virtual_bytes + length}
  end

  defp segment(kind, first, length, object_first),
    do: %{kind: kind, first: first, length: length, object_first: object_first}
end
