defmodule Vxpipe.Console.CallInspectionArtifactsBoundaryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{CallArtifact, Principal}
  alias Vxpipe.Console.CallInspection

  @tenant "tenantkey1234567"

  test "fetch_call_artifacts uses the /4 callback and does not hide valid downloads" do
    artifact = artifact("a1", 320, :complete)

    backend =
      {Vxpipe.Console.TestCallInspectionBackend,
       {self(), %{fetch_call_artifacts: {:ok, [artifact]}}}}

    authority = %Principal{tenant_key: @tenant, api_key_id: "key", scopes: MapSet.new([:admin])}

    assert {:ok, [returned]} =
             CallInspection.fetch_call_artifacts(authority, "call-id", backend: backend)

    assert returned.id == artifact.id
  end

  test "fetch_call_artifacts distinguishes backend errors from empty" do
    backend =
      {Vxpipe.Console.TestCallInspectionBackend,
       {self(), %{fetch_call_artifacts: {:error, :artifact_unavailable}}}}

    authority = %Principal{tenant_key: @tenant, api_key_id: "key", scopes: MapSet.new([:admin])}

    assert {:error, :artifact_unavailable} =
             CallInspection.fetch_call_artifacts(authority, "call-id", backend: backend)
  end

  defp artifact(id, sample_count, status) do
    {:ok, artifact} =
      CallArtifact.new(
        id: id,
        tenant_key: @tenant,
        call_id: "call-id",
        room_id: "room-id",
        incarnation_id: "incarnation-id",
        kind: :participant_track,
        participant_id: "caller-runtime",
        connection_id: "conn-1",
        track_id: "track-1",
        object_key: "calls/test/#{id}.s16le",
        object_reference: %{"object_key" => "calls/test/#{id}.s16le"},
        sample_rate: 16_000,
        channels: 1,
        sample_format: :s16le,
        started_offset_samples: 0,
        ended_offset_samples: max(sample_count, 1),
        sample_count: sample_count,
        accepted_chunks: 1,
        rejected_chunks: 0,
        gaps: [],
        status: status,
        terminal_reason: "normal"
      )

    artifact
  end
end
