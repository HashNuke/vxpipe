defmodule Vxpipe.Persistence.RecordingEvidenceProjectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.{ArtifactSpec, Manifest, Result}
  alias Vxpipe.Artifacts.Writer.Progress
  alias Vxpipe.Persistence.ArtifactResultProjection

  test "terminal manifest and call artifact carry duplicate evidence without PCM" do
    spec =
      ArtifactSpec.new(%{
        tenant_id: "tenant-dedupe",
        call_id: "call-manifest",
        room_id: "room-manifest",
        incarnation_id: "incarnation-manifest",
        artifact_id: "artifact-1",
        object_key: "calls/call-manifest/artifact-1.s16le",
        kind: :room_track,
        sample_rate: 8_000,
        channels: 1,
        sample_format: :s16le
      })
      |> then(fn {:ok, spec} -> spec end)

    progress =
      Progress.new()
      |> Progress.accept(%Vxpipe.Artifacts.Chunk{
        sequence: 0,
        offset_samples: 0,
        sample_count: 2,
        channels: 1,
        timestamp: 0,
        policy_revision: 0,
        source_participant_ids: ["room"],
        payload: <<1_000::little-16, 2_000::little-16>>,
        recording_duplicate_frames: 2,
        recording_selected_connection_id: "conn-b"
      })
      |> Progress.accept(%Vxpipe.Artifacts.Chunk{
        sequence: 1,
        offset_samples: 2,
        sample_count: 2,
        channels: 1,
        timestamp: 2,
        policy_revision: 0,
        source_participant_ids: ["room"],
        payload: <<3_000::little-16, 4_000::little-16>>,
        recording_duplicate_frames: 1,
        recording_selected_connection_id: "conn-a"
      })

    manifest = Manifest.build(spec, progress, 0, :normal)

    assert manifest.duplicate_frames == 3
    assert manifest.selected_connection_ids == ["conn-a", "conn-b"]

    # No PCM in metadata: payloads never enter the manifest.
    refute Map.has_key?(Map.from_struct(manifest), :payload)

    result = %Result{manifest: manifest, artifact: %{"object_key" => spec.object_key}}
    assert {:ok, artifact} = ArtifactResultProjection.project(result)
    assert artifact.duplicate_frames == 3
    assert artifact.selected_connection_ids == ["conn-a", "conn-b"]
  end
end
