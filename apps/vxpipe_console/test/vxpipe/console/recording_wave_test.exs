defmodule Vxpipe.Console.RecordingWaveTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.CallArtifact
  alias Vxpipe.Console.CallRecording.Source
  alias Vxpipe.Console.{RecordingWave, TestCallRecordingReader}

  test "projects bounded PCM reads and manifest gaps into one aligned WAV" do
    raw_pcm = <<1, 0, 2, 0, 3, 0, 4, 0>>
    artifact = artifact(raw_pcm)

    assert {:ok, source} =
             Source.new(artifact, {TestCallRecordingReader, {self(), raw_pcm}})

    assert {:ok, wave} = RecordingWave.new(source)
    assert wave.total_bytes == 56

    assert {:ok, payload} = read_all(wave, 3)

    assert payload ==
             <<"RIFF", 48::little-32, "WAVE", "fmt ", 16::little-32, 1::little-16, 1::little-16,
               48_000::little-32, 96_000::little-32, 2::little-16, 16::little-16, "data",
               12::little-32, 1, 0, 2, 0, 0, 0, 0, 0, 3, 0, 4, 0>>

    assert_receive {:recording_source_read, 0, 2}
  end

  test "rejects a manifest whose gaps cannot reconstruct its timeline" do
    raw_pcm = <<1, 0, 2, 0, 3, 0, 4, 0>>
    artifact = %{artifact(raw_pcm) | gaps: [%{"offset_samples" => 13, "sample_count" => 1}]}

    assert {:ok, source} =
             Source.new(artifact, {TestCallRecordingReader, {self(), raw_pcm}})

    assert {:error, :unsupported_recording_layout} = RecordingWave.new(source)
  end

  defp read_all(wave, maximum_bytes) do
    read_all(wave, 0, maximum_bytes, [])
  end

  defp read_all(wave, offset, _maximum_bytes, chunks) when offset == wave.total_bytes do
    {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp read_all(wave, offset, maximum_bytes, chunks) do
    with {:ok, chunk} <- RecordingWave.read_chunk(wave, offset, maximum_bytes) do
      read_all(wave, offset + byte_size(chunk), maximum_bytes, [chunk | chunks])
    end
  end

  defp artifact(raw_pcm) do
    {:ok, artifact} =
      CallArtifact.new(
        id: "artifact-full-mix",
        tenant_key: "tenantkey1234567",
        call_id: "call-public-id",
        room_id: "room-public-id",
        incarnation_id: "incarnation-public-id",
        kind: :full_mix,
        participant_id: nil,
        connection_id: nil,
        track_id: nil,
        object_key: "calls/tenant/call/recordings/full-mix.s16le",
        object_reference: %{"object_key" => "calls/tenant/call/recordings/full-mix.s16le"},
        sample_rate: 48_000,
        channels: 1,
        sample_format: :s16le,
        started_offset_samples: 10,
        ended_offset_samples: 16,
        sample_count: div(byte_size(raw_pcm), 2),
        accepted_chunks: 2,
        rejected_chunks: 1,
        gaps: [%{"offset_samples" => 12, "sample_count" => 2}],
        status: :incomplete,
        terminal_reason: "normal"
      )

    artifact
  end
end
