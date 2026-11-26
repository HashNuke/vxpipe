defmodule Vxpipe.Console.RecordingMatroska do
  @moduledoc """
  Presents all of a call's recording artifacts as one aligned Matroska file.

  One `A_PCM/INT/LIT` track per artifact (48 kHz, mono, s16le), ordered room
  first then by room-clock start. Every track starts at room-clock zero (the
  minimum `started_offset_samples`); gaps, denials and not-yet-started
  intervals read as silence. Clusters hold one second each with one
  SimpleBlock per track.

  The layout is bounded and seekable: no per-second, per-track or per-extent
  list is prebuilt. Cluster headers and SimpleBlock headers use fixed-width
  EBML VINTs computed from the maximum sizes, so any file offset maps
  arithmetically to prefix, cluster header, block header or track audio.
  Reads of up to 1 MiB may span headers, audio and silence gaps.
  """

  alias Vxpipe.Calls.CallArtifact
  alias Vxpipe.Console.CallRecording.Source
  alias Vxpipe.Console.RecordingTimeline

  import Bitwise

  @sample_rate 48_000
  @channels 1
  @frame_bytes 2
  @cluster_samples 48_000
  @maximum_chunk_bytes 1_048_576
  @timecode_scale 1_000_000

  @derive {Inspect, except: [:prefix, :tracks]}
  @enforce_keys [
    :tracks,
    :zero,
    :timeline_samples,
    :duration_ms,
    :prefix,
    :prefix_size,
    :total_bytes,
    :cluster_count,
    :track_count,
    :track_vint_len,
    :timestamp_fixed_len,
    :timestamp_element_len,
    :cluster_size_len,
    :block_size_len,
    :cluster_header_len,
    :block_header_len,
    :full_audio_bytes,
    :last_audio_bytes,
    :full_cluster_size,
    :last_cluster_size
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new([Source.t()]) :: {:ok, t()} | {:error, atom()}
  def new([]), do: {:error, :no_recording_artifacts}

  def new(sources) when is_list(sources) and sources != [] do
    with {:ok, ordered} <- order(sources),
         {:ok, zero, timeline_samples} <- timeline(ordered),
         {:ok, framed} <- frame(ordered, zero, timeline_samples),
         {:ok, matroska} <- layout(framed, zero, timeline_samples) do
      {:ok, matroska}
    end
  end

  def new(_), do: {:error, :unsupported_recording_layout}

  @spec track_name(map()) :: String.t()
  def track_name(map), do: CallArtifact.track_name(map)

  @spec read_chunk(t(), non_neg_integer(), pos_integer()) ::
          {:ok, binary()} | :eof | {:error, term()}
  def read_chunk(%__MODULE__{total_bytes: total_bytes}, offset, _maximum_bytes)
      when offset == total_bytes,
      do: :eof

  def read_chunk(%__MODULE__{} = matroska, offset, maximum_bytes)
      when is_integer(offset) and offset >= 0 and offset < matroska.total_bytes and
             is_integer(maximum_bytes) and maximum_bytes > 0 and
             maximum_bytes <= @maximum_chunk_bytes do
    needed = min(maximum_bytes, matroska.total_bytes - offset)
    collect(matroska, offset, needed, [])
  end

  def read_chunk(_matroska, _offset, _maximum_bytes), do: {:error, :invalid_matroska_read}

  defp order(sources) do
    if Enum.all?(sources, &match?(%Source{}, &1)) do
      ordered =
        Enum.sort_by(sources, fn source ->
          room_rank = if source.kind == :room_track, do: 0, else: 1
          {room_rank, source.started_offset_samples, source.id}
        end)

      {:ok, ordered}
    else
      {:error, :unsupported_recording_layout}
    end
  end

  defp timeline([_first | _] = sources) do
    zero = Enum.min_by(sources, & &1.started_offset_samples).started_offset_samples
    maximum = Enum.max_by(sources, & &1.ended_offset_samples).ended_offset_samples

    cond do
      not (is_integer(zero) and zero >= 0 and is_integer(maximum) and maximum > zero) ->
        {:error, :unsupported_recording_layout}

      maximum - zero <= 0 ->
        {:error, :unsupported_recording_layout}

      true ->
        {:ok, zero, maximum - zero}
    end
  end

  defp frame(ordered, zero, timeline_samples) do
    ordered
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {source, index}, {:ok, acc} ->
      case frame_track(source, index, zero, timeline_samples) do
        {:ok, track} -> {:cont, {:ok, [track | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _reason} = error -> error
    end
  end

  defp frame_track(source, index, zero, timeline_samples) do
    with true <-
           source.sample_rate == @sample_rate and source.channels == @channels and
             source.sample_format == :s16le,
         {:ok, segments} <-
           RecordingTimeline.global_segments(source, zero, timeline_samples, @frame_bytes) do
      {:ok,
       %{
         source: source,
         track_number: index,
         track_uid: index,
         name: CallArtifact.track_name(source),
         segments: List.to_tuple(segments),
         reader: source.reader
       }}
    else
      _invalid -> {:error, :unsupported_recording_layout}
    end
  end

  defp layout(tracks, zero, timeline_samples) do
    duration_ms = timeline_samples * 1_000.0 / @cluster_samples
    cluster_count = div(timeline_samples + @cluster_samples - 1, @cluster_samples)
    track_count = length(tracks)

    full_audio_bytes = @cluster_samples * @frame_bytes
    remainder = rem(timeline_samples, @cluster_samples)

    last_audio_bytes =
      if remainder == 0, do: full_audio_bytes, else: remainder * @frame_bytes

    max_timestamp = (cluster_count - 1) * 1_000
    timestamp_fixed_len = max(1, byte_size(:binary.encode_unsigned(max_timestamp)))
    timestamp_size_len = vint_length(timestamp_fixed_len)
    timestamp_element_len = 1 + timestamp_size_len + timestamp_fixed_len

    track_vint_len = vint_length(track_count)
    max_block_payload = track_vint_len + 3 + full_audio_bytes
    block_size_len = vint_length(max_block_payload)
    block_header_len = 1 + block_size_len + track_vint_len + 3

    max_cluster_payload =
      timestamp_element_len + track_count * (block_header_len + full_audio_bytes)

    cluster_size_len = vint_length(max_cluster_payload)
    cluster_header_len = 4 + cluster_size_len + timestamp_element_len
    full_cluster_size = cluster_header_len + track_count * (block_header_len + full_audio_bytes)

    last_cluster_size =
      cluster_header_len + track_count * (block_header_len + last_audio_bytes)

    clusters_total =
      if cluster_count == 1,
        do: last_cluster_size,
        else: (cluster_count - 1) * full_cluster_size + last_cluster_size

    info = info_element(duration_ms)
    tracks_element = tracks_element(tracks)
    segment_payload_size = byte_size(info) + byte_size(tracks_element) + clusters_total
    segment_header = <<0x18, 0x53, 0x80, 0x67>> <> encode_fixed_size(segment_payload_size, 8)
    prefix = ebml_header() <> segment_header <> info <> tracks_element
    prefix_size = byte_size(prefix)
    total_bytes = prefix_size + clusters_total

    {:ok,
     %__MODULE__{
       tracks: List.to_tuple(tracks),
       zero: zero,
       timeline_samples: timeline_samples,
       duration_ms: duration_ms,
       prefix: prefix,
       prefix_size: prefix_size,
       total_bytes: total_bytes,
       cluster_count: cluster_count,
       track_count: track_count,
       track_vint_len: track_vint_len,
       timestamp_fixed_len: timestamp_fixed_len,
       timestamp_element_len: timestamp_element_len,
       cluster_size_len: cluster_size_len,
       block_size_len: block_size_len,
       cluster_header_len: cluster_header_len,
       block_header_len: block_header_len,
       full_audio_bytes: full_audio_bytes,
       last_audio_bytes: last_audio_bytes,
       full_cluster_size: full_cluster_size,
       last_cluster_size: last_cluster_size
     }}
  end

  # --- Bounded seekable reads ---

  defp collect(_matroska, _offset, 0, acc),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp collect(matroska, offset, needed, acc) do
    case read_at(matroska, offset, needed) do
      {:ok, chunk} ->
        length = byte_size(chunk)
        collect(matroska, offset + length, needed - length, [chunk | acc])

      {:error, _reason} = error ->
        error
    end
  end

  defp read_at(%__MODULE__{} = matroska, offset, needed) do
    cond do
      offset < matroska.prefix_size ->
        length = min(needed, matroska.prefix_size - offset)
        {:ok, binary_part(matroska.prefix, offset, length)}

      true ->
        read_cluster_at(matroska, offset - matroska.prefix_size, needed)
    end
  end

  defp read_cluster_at(%__MODULE__{} = matroska, cluster_offset, needed) do
    %{cluster_count: count, full_cluster_size: full_size, last_cluster_size: last_size} =
      matroska

    {index, inner} =
      cond do
        count == 1 ->
          {0, cluster_offset}

        cluster_offset < (count - 1) * full_size ->
          {div(cluster_offset, full_size), rem(cluster_offset, full_size)}

        true ->
          {count - 1, cluster_offset - (count - 1) * full_size}
      end

    cond do
      inner < 0 or (index < count - 1 and inner >= full_size) or
          (index == count - 1 and inner >= last_size) ->
        {:error, :unsupported_recording_layout}

      inner < matroska.cluster_header_len ->
        header = cluster_header(matroska, index)
        length = min(needed, matroska.cluster_header_len - inner)
        {:ok, binary_part(header, inner, length)}

      true ->
        read_block_at(matroska, index, inner - matroska.cluster_header_len, needed)
    end
  end

  defp read_block_at(%__MODULE__{} = matroska, cluster_index, inner, needed) do
    audio_bytes = audio_bytes_for(matroska, cluster_index)
    stride = matroska.block_header_len + audio_bytes
    track_index = div(inner, stride)
    inner_block = rem(inner, stride)

    cond do
      track_index < 0 or track_index >= matroska.track_count ->
        {:error, :unsupported_recording_layout}

      inner_block < matroska.block_header_len ->
        header = block_header(matroska, cluster_index, track_index)
        length = min(needed, matroska.block_header_len - inner_block)
        {:ok, binary_part(header, inner_block, length)}

      true ->
        audio_inner = inner_block - matroska.block_header_len
        available = audio_bytes - audio_inner
        length = min(needed, available)
        track = elem(matroska.tracks, track_index)
        cluster_start = cluster_index * @cluster_samples
        global_first = cluster_start * @frame_bytes + audio_inner
        read_audio(track, global_first, length)
    end
  end

  defp audio_bytes_for(%__MODULE__{cluster_count: count} = matroska, index)
       when index < count - 1,
       do: matroska.full_audio_bytes

  defp audio_bytes_for(%__MODULE__{} = matroska, _index), do: matroska.last_audio_bytes

  defp cluster_header(%__MODULE__{} = matroska, index) do
    timestamp = index * 1_000
    fixed_len = matroska.timestamp_fixed_len
    timestamp_bytes = <<timestamp::big-size(fixed_len)-unit(8)>>
    timestamp_size_vint = encode_vint_fixed(fixed_len, vint_length(fixed_len))
    timestamp_element = <<0xE7>> <> timestamp_size_vint <> timestamp_bytes
    audio_bytes = audio_bytes_for(matroska, index)

    payload_size =
      matroska.timestamp_element_len +
        matroska.track_count * (matroska.block_header_len + audio_bytes)

    <<0x1F, 0x43, 0xB6, 0x75>> <>
      encode_vint_fixed(payload_size, matroska.cluster_size_len) <>
      timestamp_element
  end

  defp block_header(%__MODULE__{} = matroska, cluster_index, track_index) do
    track = elem(matroska.tracks, track_index)
    audio_bytes = audio_bytes_for(matroska, cluster_index)
    payload_size = matroska.track_vint_len + 3 + audio_bytes

    <<0xA3>> <>
      encode_vint_fixed(payload_size, matroska.block_size_len) <>
      encode_vint_fixed(track.track_number, matroska.track_vint_len) <>
      <<0, 0, 0x80>>
  end

  defp read_audio(track, global_first, length) do
    read_audio_segments(
      track.segments,
      track.reader,
      global_first,
      global_first + length,
      []
    )
  end

  defp read_audio_segments(_segments, _reader, cursor, stop, acc) when cursor >= stop do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp read_audio_segments(segments, reader, cursor, stop, acc) do
    case find_segment(segments, cursor, 0, tuple_size(segments) - 1) do
      nil ->
        {:error, :unsupported_recording_layout}

      %{kind: :silence} = segment ->
        length = min(stop, segment.first + segment.length) - cursor

        read_audio_segments(segments, reader, cursor + length, stop, [
          :binary.copy(<<0>>, length) | acc
        ])

      %{kind: :object} = segment ->
        length = min(stop, segment.first + segment.length) - cursor
        object_first = segment.object_first + cursor - segment.first

        case Vxpipe.Console.CallRecording.Reader.read_range(
               reader,
               object_first,
               object_first + length - 1
             ) do
          {:ok, chunk} when byte_size(chunk) == length ->
            read_audio_segments(segments, reader, cursor + length, stop, [chunk | acc])

          {:ok, _chunk} ->
            {:error, :invalid_recording_range}

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp find_segment(_segments, _offset, low, high) when low > high, do: nil

  defp find_segment(segments, offset, low, high) do
    index = div(low + high, 2)
    segment = elem(segments, index)

    cond do
      offset < segment.first -> find_segment(segments, offset, low, index - 1)
      offset >= segment.first + segment.length -> find_segment(segments, offset, index + 1, high)
      true -> segment
    end
  end

  defp ebml_header do
    payload =
      encode_uint(0x4286, 1) <>
        encode_uint(0x42F7, 1) <>
        encode_uint(0x42F2, 4) <>
        encode_uint(0x42F3, 8) <>
        encode_string(0x4282, "matroska") <>
        encode_uint(0x4287, 4) <>
        encode_uint(0x4285, 2)

    encode_element(0x1A45DFA3, payload)
  end

  defp info_element(duration_ms) do
    payload =
      encode_uint(0x2AD7B1, @timecode_scale) <>
        encode_float64(0x4489, duration_ms) <>
        encode_string(0x4D80, "vxpipe") <>
        encode_string(0x5741, "vxpipe")

    encode_element(0x1549A966, payload)
  end

  defp tracks_element(tracks) do
    payload =
      tracks
      |> Enum.map(&track_entry/1)
      |> IO.iodata_to_binary()

    encode_element(0x1654AE6B, payload)
  end

  defp track_entry(track) do
    audio =
      encode_float32(0xB5, 48_000.0) <>
        encode_uint(0x9F, @channels) <>
        encode_uint(0x6264, 16)

    payload =
      encode_uint(0xD7, track.track_number) <>
        encode_uint(0x73C5, track.track_uid) <>
        encode_uint(0x83, 2) <>
        encode_uint(0x88, 1) <>
        encode_string(0x86, "A_PCM/INT/LIT") <>
        encode_string(0x536E, track.name) <>
        encode_string(0x22B59C, "und") <>
        encode_element(0xE1, audio)

    encode_element(0xAE, payload)
  end

  defp encode_element(id, payload) do
    :binary.encode_unsigned(id) <> encode_vint_size(byte_size(payload)) <> payload
  end

  defp encode_uint(id, value) when is_integer(value) and value >= 0 do
    encode_element(id, :binary.encode_unsigned(value))
  end

  defp encode_string(id, value) when is_binary(value) do
    encode_element(id, value)
  end

  defp encode_float32(id, value) do
    encode_element(id, <<value::32-float-big>>)
  end

  defp encode_float64(id, value) do
    encode_element(id, <<value::64-float-big>>)
  end

  defp encode_vint_size(value) when is_integer(value) and value >= 0 do
    length = vint_length(value)
    encode_vint_fixed(value, length)
  end

  defp encode_vint_fixed(value, length)
       when is_integer(value) and value >= 0 and is_integer(length) and length >= 1 and
              length <= 8 do
    encoded = 1 <<< (7 * length) ||| value
    <<encoded::size(length)-unit(8)>>
  end

  defp vint_length(value, length \\ 1) do
    maximum = (1 <<< (7 * length)) - 2

    if value <= maximum or length == 8,
      do: length,
      else: vint_length(value, length + 1)
  end

  defp encode_fixed_size(value, 8) when is_integer(value) and value >= 0 do
    <<0x01, value::56-big>>
  end
end
