defmodule Vxpipe.Console.RecordingMatroskaTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Vxpipe.Calls.CallArtifact
  alias Vxpipe.Console.CallRecording.Source
  alias Vxpipe.Console.{RecordingMatroska, TestCallRecordingReader}

  test "builds one aligned Matroska file from three sources with gaps and late starts" do
    room_payload = :binary.copy(<<16, 0>>, 96_000)
    caller_payload = :binary.copy(<<32, 0>>, 96_000)
    reconnect_payload = :binary.copy(<<48, 0>>, 96_000)

    sources = [
      source(room_artifact(), room_payload),
      source(caller_artifact(), caller_payload),
      source(reconnect_artifact(), reconnect_payload)
    ]

    assert {:ok, matroska} = RecordingMatroska.new(sources)
    assert matroska.total_bytes > 0

    assert {:ok, file} = read_all(matroska, 65_537)
    assert byte_size(file) == matroska.total_bytes

    assert {:ok, parsed} = parse_matroska(file)
    assert parsed.doc_type == "matroska"
    assert parsed.track_names == ["room", "caller", "caller-1"]
    assert parsed.timecode_scale == 1_000_000
    assert parsed.duration_ms == 3_000

    assert Enum.uniq(Enum.map(parsed.tracks, &byte_size(&1.audio))) |> length() == 1
    assert byte_size(hd(parsed.tracks).audio) == 144_000 * 2

    [room, caller, reconnect] = parsed.tracks

    # Room: two seconds of audio, one second of trailing silence.
    assert binary_part(room.audio, 0, 96_000 * 2) == room_payload
    assert binary_part(room.audio, 96_000 * 2, 48_000 * 2) == :binary.copy(<<0>>, 48_000 * 2)

    # Caller: audio, one-second gap silence, audio.
    assert binary_part(caller.audio, 0, 48_000 * 2) == binary_part(caller_payload, 0, 48_000 * 2)

    assert binary_part(caller.audio, 48_000 * 2, 48_000 * 2) ==
             :binary.copy(<<0>>, 48_000 * 2)

    assert binary_part(caller.audio, 96_000 * 2, 48_000 * 2) ==
             binary_part(caller_payload, 48_000 * 2, 48_000 * 2)

    # Reconnect: one second of leading silence, then two seconds of audio.
    assert binary_part(reconnect.audio, 0, 48_000 * 2) == :binary.copy(<<0>>, 48_000 * 2)

    assert binary_part(reconnect.audio, 48_000 * 2, 96_000 * 2) == reconnect_payload
  end

  test "PCM blocks are seekable and the Segment identifies its muxer and writer" do
    room = source(room_artifact(), :binary.copy(<<16, 0>>, 96_000))
    assert {:ok, layout} = RecordingMatroska.new([room])
    assert {:ok, bytes} = read_all(layout, 65_537)
    assert :binary.match(bytes, <<0x81, 0, 0, 0x80, 16, 0, 16, 0>>) != :nomatch
    assert :binary.match(bytes, <<0x4D, 0x80, 0x86, "vxpipe">>) != :nomatch
    assert :binary.match(bytes, <<0x57, 0x41, 0x86, "vxpipe">>) != :nomatch
  end

  test "a sparse 24-hour call supports reading a range from its final second" do
    ending = 24 * 3_600 * 48_000

    early = %{
      room_artifact()
      | sample_count: 1,
        started_offset_samples: 0,
        ended_offset_samples: 1,
        gaps: []
    }

    late = %{
      caller_artifact()
      | sample_count: 1,
        started_offset_samples: ending - 1,
        ended_offset_samples: ending,
        gaps: []
    }

    assert {:ok, layout} =
             RecordingMatroska.new([source(early, <<1, 0>>), source(late, <<2, 0>>)])

    assert {:ok, <<0, 0, 2, 0>>} = RecordingMatroska.read_chunk(layout, layout.total_bytes - 4, 4)
  end

  test "track names fall back to participant ids and suffix reconnections" do
    assert RecordingMatroska.track_name(%{kind: :room_track}) == "room"

    assert RecordingMatroska.track_name(%{
             kind: :participant_track,
             participant_key: "caller",
             reconnection: 0
           }) == "caller"

    assert RecordingMatroska.track_name(%{
             kind: :participant_track,
             participant_key: "caller",
             reconnection: 1
           }) == "caller-1"

    assert RecordingMatroska.track_name(%{
             kind: :participant_track,
             participant_id: "part_123",
             participant_key: nil,
             reconnection: 0
           }) == "part_123"

    assert RecordingMatroska.track_name(%{
             kind: :participant_track,
             participant_id: "part_123",
             participant_key: nil,
             reconnection: 1
           }) == "part_123-1"

    assert RecordingMatroska.track_name(%{kind: :room_track}) ==
             Vxpipe.Calls.CallArtifact.track_name(%{kind: :room_track})
  end

  test "bounded layout maps late range on long sparse timeline without prebuilt extents" do
    timeline_samples = 48_000 * 20
    room_payload = :binary.copy(<<16, 0>>, 48_000)
    late_payload = :binary.copy(<<32, 0>>, 48_000)

    room_artifact = %CallArtifact{
      id: "artifact-room-sparse",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :room_track,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      participant_key: nil,
      reconnection: 0,
      object_key: "calls/tenant/call/recordings/room-sparse.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/room-sparse.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: timeline_samples,
      sample_count: 48_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [%{"offset_samples" => 48_000, "sample_count" => timeline_samples - 48_000}],
      status: :complete,
      terminal_reason: "source_ended"
    }

    late_artifact = %CallArtifact{
      id: "artifact-late",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :participant_track,
      participant_id: "part_late",
      connection_id: "conn_late",
      track_id: "track_late",
      participant_key: "late",
      reconnection: 0,
      object_key: "calls/tenant/call/recordings/late.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/late.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: timeline_samples - 48_000,
      ended_offset_samples: timeline_samples,
      sample_count: 48_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }

    sources = [source(room_artifact, room_payload), source(late_artifact, late_payload)]
    assert {:ok, matroska} = RecordingMatroska.new(sources)
    refute Map.has_key?(matroska, :extents)
    assert matroska.cluster_count == 20
    assert matroska.track_count == 2

    # Late range: last cluster audio for both tracks.
    total = matroska.total_bytes

    assert total ==
             matroska.prefix_size + 19 * matroska.full_cluster_size + matroska.last_cluster_size

    last_cluster_first = total - matroska.last_cluster_size
    assert {:ok, chunk} = RecordingMatroska.read_chunk(matroska, last_cluster_first, 1_048_576)
    assert byte_size(chunk) > 0

    # Last cluster contains silence for room (gap) and audio for late track.
    # Read full file in 1MiB chunks split across headers/gaps and verify late audio.
    assert {:ok, file} = read_all(matroska, 1_048_576)
    assert byte_size(file) == total
    assert {:ok, parsed} = parse_matroska(file)
    assert parsed.track_names == ["room", "late"]
    [room, late] = parsed.tracks
    assert byte_size(room.audio) == timeline_samples * 2
    assert binary_part(room.audio, 0, 48_000 * 2) == room_payload

    assert binary_part(room.audio, 48_000 * 2, (timeline_samples - 48_000) * 2) ==
             :binary.copy(<<0>>, (timeline_samples - 48_000) * 2)

    assert binary_part(late.audio, 0, (timeline_samples - 48_000) * 2) ==
             :binary.copy(<<0>>, (timeline_samples - 48_000) * 2)

    assert binary_part(late.audio, (timeline_samples - 48_000) * 2, 48_000 * 2) == late_payload
  end

  test "128+ tracks use proper EBML track-number VINT and fixed-width blocks" do
    payload = :binary.copy(<<7, 0>>, 48_000)

    room_artifact_1s = %CallArtifact{
      id: "artifact-room-1s",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :room_track,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      participant_key: nil,
      reconnection: 0,
      object_key: "calls/tenant/call/recordings/room-1s.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/room-1s.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 48_000,
      sample_count: 48_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }

    room = source(room_artifact_1s, payload)

    participants =
      for n <- 1..129 do
        artifact = %CallArtifact{
          id: "artifact-#{n}",
          tenant_key: "tenantkey1234567",
          call_id: "call-public-id",
          room_id: "room-public-id",
          incarnation_id: "incarnation-public-id",
          kind: :participant_track,
          participant_id: "part_#{n}",
          connection_id: "conn_#{n}",
          track_id: "track_#{n}",
          participant_key: "p#{n}",
          reconnection: 0,
          object_key: "calls/tenant/call/recordings/p#{n}.s16le",
          object_reference: %{"object_key" => "calls/tenant/call/recordings/p#{n}.s16le"},
          sample_rate: 48_000,
          channels: 1,
          sample_format: :s16le,
          started_offset_samples: 0,
          ended_offset_samples: 48_000,
          sample_count: 48_000,
          accepted_chunks: 1,
          rejected_chunks: 0,
          gaps: [],
          status: :complete,
          terminal_reason: "source_ended"
        }

        source(artifact, payload)
      end

    sources = [room | participants]
    assert {:ok, matroska} = RecordingMatroska.new(sources)
    assert matroska.track_count == 130
    assert matroska.track_vint_len == 2
    assert matroska.cluster_count == 1

    assert {:ok, file} = read_all(matroska, 1_048_576)
    assert byte_size(file) == matroska.total_bytes
    assert {:ok, parsed} = parse_matroska(file)
    assert length(parsed.tracks) == 130
    assert Enum.sort(parsed.track_names) |> length() == 130
    # Track numbers decode correctly, including 2-byte VINTs for 127+.
    numbers = Enum.map(parsed.track_numbers, & &1) |> Enum.sort()
    assert numbers == Enum.to_list(1..130)
    assert Enum.all?(parsed.tracks, &(byte_size(&1.audio) == 48_000 * 2))
  end

  test "duration is real float without ceil to ms" do
    payload = :binary.copy(<<9, 0>>, 48_001)

    artifact = %CallArtifact{
      id: "artifact-duration",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :room_track,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      participant_key: nil,
      reconnection: 0,
      object_key: "calls/tenant/call/recordings/duration.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/duration.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 48_001,
      sample_count: 48_001,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }

    assert {:ok, matroska} = RecordingMatroska.new([source(artifact, payload)])
    expected = 48_001 * 1_000.0 / 48_000
    assert_in_delta matroska.duration_ms, expected, 0.0001
    refute matroska.duration_ms == 1_001
    assert {:ok, file} = read_all(matroska, 1_048_576)
    assert {:ok, parsed} = parse_matroska(file)
    assert_in_delta parsed.duration_ms, expected, 0.01
  end

  defp source(artifact, payload) do
    {:ok, source} = Source.new(artifact, {TestCallRecordingReader, {self(), payload}})
    source
  end

  defp room_artifact do
    %CallArtifact{
      id: "artifact-room",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :room_track,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      participant_key: nil,
      reconnection: 0,
      object_key: "calls/tenant/call/recordings/room.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/room.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 96_000,
      sample_count: 96_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end

  defp caller_artifact do
    %CallArtifact{
      id: "artifact-caller",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :participant_track,
      participant_id: "part_caller",
      connection_id: "conn_caller",
      track_id: "track_caller",
      participant_key: "caller",
      reconnection: 0,
      object_key: "calls/tenant/call/recordings/caller.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/caller.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 144_000,
      sample_count: 96_000,
      accepted_chunks: 2,
      rejected_chunks: 0,
      gaps: [%{"offset_samples" => 48_000, "sample_count" => 48_000}],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end

  defp reconnect_artifact do
    %CallArtifact{
      id: "artifact-caller-1",
      tenant_key: "tenantkey1234567",
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      kind: :participant_track,
      participant_id: "part_caller",
      connection_id: "conn_caller_2",
      track_id: "track_caller_2",
      participant_key: "caller",
      reconnection: 1,
      object_key: "calls/tenant/call/recordings/caller-1.s16le",
      object_reference: %{"object_key" => "calls/tenant/call/recordings/caller-1.s16le"},
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 48_000,
      ended_offset_samples: 144_000,
      sample_count: 96_000,
      accepted_chunks: 1,
      rejected_chunks: 0,
      gaps: [],
      status: :complete,
      terminal_reason: "source_ended"
    }
  end

  defp read_all(matroska, maximum_bytes) do
    read_all(matroska, 0, maximum_bytes, [])
  end

  defp read_all(matroska, offset, _maximum_bytes, chunks) when offset == matroska.total_bytes do
    {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp read_all(matroska, offset, maximum_bytes, chunks) do
    with {:ok, chunk} <- RecordingMatroska.read_chunk(matroska, offset, maximum_bytes) do
      read_all(matroska, offset + byte_size(chunk), maximum_bytes, [chunk | chunks])
    end
  end

  # Minimal EBML/Matroska parser for the writer below: header, segment info,
  # track names and per-track concatenated SimpleBlock audio.
  defp parse_matroska(<<0x1A, 0x45, 0xDF, 0xA3, rest::binary>>) do
    with {:ok, header_size, after_size} <- read_vint_size(rest),
         {:ok, header_payload, after_segment_id} <- read_payload(after_size, header_size),
         {:ok, header_fields} <- parse_elements(header_payload),
         "matroska" <- Map.get(header_fields, 0x4282, :missing_doctype),
         <<0x18, 0x53, 0x80, 0x67, segment_rest::binary>> <- after_segment_id,
         {:ok, segment_size, after_segment_size} <- read_vint_size(segment_rest),
         {:ok, segment_body, _tail} <- read_payload(after_segment_size, segment_size),
         {:ok, info, tracks, clusters} <- parse_segment(segment_body) do
      {:ok,
       %{
         doc_type: "matroska",
         timecode_scale: Map.fetch!(info, 0x2AD7B1),
         duration_ms: Map.fetch!(info, 0x4489),
         track_names: Enum.map(tracks, & &1.name),
         track_numbers: Enum.map(tracks, & &1.number),
         tracks: attach_audio(tracks, clusters)
       }}
    else
      _ -> {:error, :invalid_matroska}
    end
  end

  defp parse_matroska(_), do: {:error, :invalid_matroska}

  defp attach_audio(tracks, clusters) do
    number_to_name = Map.new(tracks, &{&1.number, &1.name})

    audio_by_track =
      Enum.reduce(clusters, Map.new(tracks, &{&1.name, []}), fn cluster, acc ->
        Enum.reduce(cluster.blocks, acc, fn block, inner ->
          name = Map.fetch!(number_to_name, block.track_number)
          Map.update!(inner, name, &[block.audio | &1])
        end)
      end)

    Enum.map(tracks, fn track ->
      audio =
        audio_by_track |> Map.fetch!(track.name) |> Enum.reverse() |> IO.iodata_to_binary()

      %{name: track.name, audio: audio}
    end)
  end

  defp parse_segment(body) do
    with {:ok, elements} <- parse_elements_raw(body),
         %{0x1549A966 => info_bin, 0x1654AE6B => tracks_bin} <- Map.new(elements),
         {:ok, info} <- parse_elements(info_bin),
         {:ok, track_entries} <- parse_tracks(tracks_bin) do
      clusters =
        elements
        |> Enum.filter(fn {id, _} -> id == 0x1F43B675 end)
        |> Enum.map(fn {_, bin} -> parse_cluster(bin) end)

      {:ok, info, track_entries, clusters}
    else
      _ -> {:error, :invalid_segment}
    end
  end

  defp parse_tracks(bin) do
    with {:ok, elements} <- parse_elements_raw(bin) do
      entries =
        elements
        |> Enum.filter(fn {id, _} -> id == 0xAE end)
        |> Enum.map(fn {_, entry_bin} ->
          {:ok, fields} = parse_elements(entry_bin)
          number = Map.fetch!(fields, 0xD7)
          name = Map.get(fields, 0x536E, "track-#{number}")
          %{number: number, name: name}
        end)

      {:ok, Enum.sort_by(entries, & &1.number)}
    end
  end

  defp parse_cluster(bin) do
    {:ok, elements} = parse_elements_raw(bin)

    timestamp =
      Enum.find_value(elements, 0, fn
        {0xE7, value} -> decode_uint(value)
        _ -> nil
      end)

    blocks =
      elements
      |> Enum.filter(fn {id, _} -> id == 0xA3 end)
      |> Enum.map(fn {_, block_bin} ->
        {track_number, <<_rel::16-big, _flags, audio::binary>>} = decode_track_vint(block_bin)

        %{
          track_number: track_number,
          name: "track-#{track_number}",
          audio: audio,
          timestamp: timestamp
        }
      end)

    %{timestamp: timestamp, blocks: blocks}
  end

  defp decode_track_vint(<<first, _::binary>> = bin) do
    length = vint_octets(first)
    <<vint::binary-size(length), rest::binary>> = bin
    {decode_vint(vint), rest}
  end

  # NOTE: block names are resolved by track number -> name using the segment track
  # table. The attach step above uses names; we patch numbers to names here by
  # re-reading the global track table through process dictionary set in parse.
  defp parse_elements(bin), do: parse_elements(bin, %{})

  defp parse_elements(<<>>, acc), do: {:ok, acc}

  defp parse_elements(bin, acc) do
    with {:ok, id, after_id} <- read_id(bin),
         {:ok, size, payload_bin} <- read_vint_size(after_id),
         {:ok, payload, rest} <- read_payload(payload_bin, size) do
      value =
        case id do
          0x4282 -> payload
          0x2AD7B1 -> decode_uint(payload)
          0x4489 -> decode_float(payload)
          0xD7 -> decode_uint(payload)
          0x536E -> payload
          0xE7 -> decode_uint(payload)
          _ -> payload
        end

      parse_elements(rest, Map.put(acc, id, value))
    else
      _ -> {:error, :invalid_elements}
    end
  end

  defp parse_elements_raw(bin), do: parse_elements_raw(bin, [])

  defp parse_elements_raw(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_elements_raw(bin, acc) do
    with {:ok, id, after_id} <- read_id(bin),
         {:ok, size, payload_bin} <- read_vint_size(after_id),
         {:ok, payload, rest} <- read_payload(payload_bin, size) do
      parse_elements_raw(rest, [{id, payload} | acc])
    else
      _ -> {:error, :invalid_elements}
    end
  end

  defp read_id(<<0x1A, 0x45, 0xDF, 0xA3, rest::binary>>), do: {:ok, 0x1A45DFA3, rest}
  defp read_id(<<0x18, 0x53, 0x80, 0x67, rest::binary>>), do: {:ok, 0x18538067, rest}
  defp read_id(<<0x16, 0x54, 0xAE, 0x6B, rest::binary>>), do: {:ok, 0x1654AE6B, rest}
  defp read_id(<<0x1F, 0x43, 0xB6, 0x75, rest::binary>>), do: {:ok, 0x1F43B675, rest}
  defp read_id(<<0x15, 0x49, 0xA9, 0x66, rest::binary>>), do: {:ok, 0x1549A966, rest}
  defp read_id(<<0x2A, 0xD7, 0xB1, rest::binary>>), do: {:ok, 0x2AD7B1, rest}
  defp read_id(<<0x22, 0xB5, 0x9C, rest::binary>>), do: {:ok, 0x22B59C, rest}
  defp read_id(<<0x53, 0x6E, rest::binary>>), do: {:ok, 0x536E, rest}
  defp read_id(<<0x62, 0x64, rest::binary>>), do: {:ok, 0x6264, rest}
  defp read_id(<<0x73, 0xC5, rest::binary>>), do: {:ok, 0x73C5, rest}
  defp read_id(<<0x44, 0x89, rest::binary>>), do: {:ok, 0x4489, rest}
  defp read_id(<<first, rest::binary>>) when first >= 0x80, do: {:ok, first, rest}

  defp read_id(<<first, second, rest::binary>>) when first >= 0x40,
    do: {:ok, (first <<< 8) + second, rest}

  defp read_id(_), do: {:error, :invalid_id}

  defp read_vint_size(<<first, _::binary>> = bin) do
    length = vint_octets(first)

    if byte_size(bin) >= length do
      <<prefix::binary-size(length), rest::binary>> = bin
      {:ok, decode_vint(prefix), rest}
    else
      {:error, :invalid_size}
    end
  end

  defp read_vint_size(_), do: {:error, :invalid_size}

  defp vint_octets(first) when first >= 0x80, do: 1
  defp vint_octets(first) when first >= 0x40, do: 2
  defp vint_octets(first) when first >= 0x20, do: 3
  defp vint_octets(first) when first >= 0x10, do: 4
  defp vint_octets(first) when first >= 0x08, do: 5
  defp vint_octets(first) when first >= 0x04, do: 6
  defp vint_octets(first) when first >= 0x02, do: 7
  defp vint_octets(_), do: 8

  defp decode_vint(prefix) do
    size = byte_size(prefix)
    unsigned = :binary.decode_unsigned(prefix)
    unsigned - (1 <<< (7 * size))
  end

  defp read_payload(bin, size) when byte_size(bin) >= size do
    <<payload::binary-size(size), rest::binary>> = bin
    {:ok, payload, rest}
  end

  defp read_payload(_, _), do: {:error, :short_payload}

  defp decode_uint(<<>>), do: 0
  defp decode_uint(bin), do: :binary.decode_unsigned(bin)

  defp decode_float(<<value::32-float-big>>), do: value
  defp decode_float(<<value::64-float-big>>), do: value
  defp decode_float(_), do: 0.0
end
