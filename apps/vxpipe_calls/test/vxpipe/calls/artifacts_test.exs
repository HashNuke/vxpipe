defmodule Vxpipe.Calls.ArtifactsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallArtifact, Principal, TestArtifactRepository}

  test "stores terminal recording metadata and authorizes tenant-scoped reads" do
    repository = start_supervised!(TestArtifactRepository)
    options = [artifact_repository: TestArtifactRepository.repository(repository)]

    assert {:ok, artifact} = CallArtifact.new(attributes())
    assert {:ok, ^artifact} = Calls.archive_call_artifact(artifact, options)

    principal = %Principal{
      tenant_key: artifact.tenant_key,
      api_key_id: "key-calls",
      scopes: MapSet.new([:calls])
    }

    assert {:ok, [^artifact]} = Calls.fetch_call_artifacts(principal, artifact.call_id, options)

    unauthorized = %{principal | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Calls.fetch_call_artifacts(unauthorized, artifact.call_id, options)

    assert TestArtifactRepository.operations(repository) == [
             {:store, artifact.id},
             {:fetch, artifact.tenant_key, artifact.call_id}
           ]
  end

  defp attributes do
    [
      id: "artifact-full-mix",
      tenant_key: "AAAAAAAAAAAAAAAA",
      call_id: "44444444-4444-4444-8444-444444444444",
      room_id: "55555555-5555-4555-8555-555555555555",
      incarnation_id: "rinc_archive-test",
      kind: :full_mix,
      participant_id: nil,
      connection_id: nil,
      track_id: nil,
      object_key: "calls/tenant/call/recordings/artifact-full-mix.s16le",
      object_reference: %{
        "object_key" => "calls/tenant/call/recordings/artifact-full-mix.s16le",
        "etag" => "etag-full-mix"
      },
      sample_rate: 48_000,
      channels: 1,
      sample_format: :s16le,
      started_offset_samples: 0,
      ended_offset_samples: 2_880,
      sample_count: 1_920,
      accepted_chunks: 2,
      rejected_chunks: 1,
      gaps: [%{"offset_samples" => 960, "sample_count" => 960}],
      status: :incomplete,
      terminal_reason: "normal"
    ]
  end
end
