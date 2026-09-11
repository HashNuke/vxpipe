defmodule Vxpipe.Console.RecordingWave do
  @moduledoc "Presents one signed-16 PCM recording as an aligned virtual RIFF/WAVE file."

  alias Vxpipe.Console.CallRecording.{Reader, Source}

  @header_bytes 44
  @maximum_chunk_bytes 1_048_576
  @maximum_uint32 4_294_967_295

  @derive {Inspect, except: [:source, :header, :segments]}
  @enforce_keys [:source, :header, :segments, :total_bytes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(Source.t()) :: {:ok, t()} | {:error, atom()}
  def new(%Source{} = source) do
    with {:ok, frame_bytes} <- format(source),
         {:ok, timeline_samples} <- timeline_samples(source),
         {:ok, segments} <- segments(source, timeline_samples, frame_bytes),
         {:ok, data_bytes} <- data_bytes(timeline_samples, frame_bytes),
         {:ok, header} <- header(source, frame_bytes, data_bytes) do
      {:ok,
       %__MODULE__{
         source: source,
         header: header,
         segments: segments,
         total_bytes: @header_bytes + data_bytes
       }}
    end
  end

  def new(_source), do: {:error, :unsupported_recording_layout}

  @spec read_chunk(t(), non_neg_integer(), pos_integer()) ::
          {:ok, binary()} | :eof | {:error, term()}
  def read_chunk(%__MODULE__{total_bytes: total_bytes}, offset, _maximum_bytes)
      when offset == total_bytes,
      do: :eof

  def read_chunk(%__MODULE__{} = wave, offset, maximum_bytes)
      when is_integer(offset) and offset >= 0 and offset < wave.total_bytes and
             is_integer(maximum_bytes) and maximum_bytes > 0 and
             maximum_bytes <= @maximum_chunk_bytes do
    if offset < @header_bytes,
      do: read_header(wave, offset, maximum_bytes),
      else: read_data(wave, offset - @header_bytes, maximum_bytes)
  end

  def read_chunk(_wave, _offset, _maximum_bytes), do: {:error, :invalid_wave_read}

  defp format(%Source{sample_format: :s16le, channels: channels, sample_rate: sample_rate})
       when is_integer(channels) and channels > 0 and channels <= 8 and
              is_integer(sample_rate) and sample_rate > 0 do
    frame_bytes = channels * 2
    byte_rate = sample_rate * frame_bytes

    if frame_bytes <= 65_535 and byte_rate <= @maximum_uint32,
      do: {:ok, frame_bytes},
      else: {:error, :unsupported_recording_layout}
  end

  defp format(_source), do: {:error, :unsupported_recording_layout}

  defp timeline_samples(%Source{
         started_offset_samples: started,
         ended_offset_samples: ended,
         sample_count: sample_count
       })
       when is_integer(started) and started >= 0 and is_integer(ended) and ended > started and
              is_integer(sample_count) and sample_count > 0 do
    {:ok, ended - started}
  end

  defp timeline_samples(_source), do: {:error, :unsupported_recording_layout}

  defp segments(source, timeline_samples, frame_bytes) do
    expected_gap_samples = timeline_samples - source.sample_count

    with true <- expected_gap_samples >= 0,
         {:ok, segments, raw_samples, gap_samples} <-
           build_segments(
             source.gaps,
             source.started_offset_samples,
             source.ended_offset_samples,
             frame_bytes
           ),
         true <- raw_samples == source.sample_count,
         true <- gap_samples == expected_gap_samples do
      {:ok, segments}
    else
      _invalid -> {:error, :unsupported_recording_layout}
    end
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

  defp data_bytes(timeline_samples, frame_bytes) do
    data_bytes = timeline_samples * frame_bytes

    if data_bytes <= @maximum_uint32 - 36,
      do: {:ok, data_bytes},
      else: {:error, :unsupported_recording_layout}
  end

  defp header(source, frame_bytes, data_bytes) do
    riff_bytes = data_bytes + 36
    byte_rate = source.sample_rate * frame_bytes

    {:ok,
     <<"RIFF", riff_bytes::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16,
       source.channels::little-16, source.sample_rate::little-32, byte_rate::little-32,
       frame_bytes::little-16, 16::little-16, "data", data_bytes::little-32>>}
  end

  defp read_header(wave, offset, maximum_bytes) do
    length = min(maximum_bytes, @header_bytes - offset)
    {:ok, binary_part(wave.header, offset, length)}
  end

  defp read_data(wave, data_offset, maximum_bytes) do
    case Enum.find(wave.segments, &inside?(&1, data_offset)) do
      %{kind: :silence} = segment ->
        {:ok, :binary.copy(<<0>>, chunk_length(segment, data_offset, maximum_bytes))}

      %{kind: :object} = segment ->
        length = chunk_length(segment, data_offset, maximum_bytes)
        object_first = segment.object_first + data_offset - segment.first
        Reader.read_range(wave.source.reader, object_first, object_first + length - 1)

      nil ->
        {:error, :unsupported_recording_layout}
    end
  end

  defp inside?(segment, offset),
    do: offset >= segment.first and offset < segment.first + segment.length

  defp chunk_length(segment, offset, maximum_bytes),
    do: min(maximum_bytes, segment.first + segment.length - offset)
end
