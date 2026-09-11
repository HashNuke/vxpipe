defmodule Vxpipe.Artifacts.S3ObjectStoreTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Manifest, S3ObjectStore, TestS3Client}

  @part_size_bytes 5 * 1_024 * 1_024

  test "buffers PCM into valid multipart parts and uploads the final short part" do
    spec = artifact_spec()

    options = [
      bucket: "recordings-test",
      client: TestS3Client,
      client_options: [observer: self()],
      part_size_bytes: @part_size_bytes
    ]

    assert {:ok, session} = S3ObjectStore.open(spec, options)
    assert_receive {:test_s3_initiated, "recordings-test", object_key}
    assert object_key == spec.object_key

    first_payload = :binary.copy(<<1, 0>>, div(@part_size_bytes, 4))
    second_payload = :binary.copy(<<2, 0>>, div(@part_size_bytes, 4))
    final_payload = <<3, 0, 4, 0>>

    assert {:ok, session} =
             S3ObjectStore.write_chunk(session, chunk(0, 0, first_payload), options)

    refute_receive {:test_s3_part_uploaded, _, _, _, _, _}

    first_samples = div(byte_size(first_payload), 2)

    assert {:ok, session} =
             S3ObjectStore.write_chunk(
               session,
               chunk(1, first_samples, second_payload),
               options
             )

    assert_receive {:test_s3_part_uploaded, "recordings-test", ^object_key, "upload-test", 1,
                    first_part}

    assert first_part == first_payload <> second_payload

    second_samples = div(byte_size(second_payload), 2)

    assert {:ok, session} =
             S3ObjectStore.write_chunk(
               session,
               chunk(2, first_samples + second_samples, final_payload),
               options
             )

    manifest = Manifest.build(spec, progress(first_samples + second_samples + 2), 0, :normal)

    assert {:ok, artifact} = S3ObjectStore.complete(session, manifest, options)
    assert artifact.object_key == object_key

    assert_receive {:test_s3_part_uploaded, "recordings-test", ^object_key, "upload-test", 2,
                    ^final_payload}

    assert_receive {:test_s3_completed, "recordings-test", ^object_key, "upload-test",
                    [{1, "etag-1"}, {2, "etag-2"}]}

    refute_receive {:test_s3_aborted, _, _, _}
  end

  defp artifact_spec do
    %ArtifactSpec{
      tenant_id: "tenant-test",
      call_id: "call-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      artifact_id: "artifact-test",
      object_key: "calls/tenant/call/incarnation/recordings/artifact-test.s16le",
      kind: :full_mix,
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le
    }
  end

  defp chunk(sequence, offset_samples, payload) do
    %Chunk{
      sequence: sequence,
      offset_samples: offset_samples,
      sample_count: div(byte_size(payload), 2),
      channels: 1,
      timestamp: offset_samples,
      policy_revision: 0,
      source_participant_ids: [],
      payload: payload
    }
  end

  defp progress(sample_count) do
    %{
      accepted_chunks: 3,
      failed_chunks: 0,
      sample_count: sample_count,
      started_offset_samples: 0,
      ended_offset_samples: sample_count,
      gaps: []
    }
  end
end
