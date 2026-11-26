defmodule Vxpipe.Persistence.CallDetailsRecordingSnapshotTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{CallArtifact, CallFact}
  alias Vxpipe.CallEngine.ResolvedCallPlan

  alias Vxpipe.Persistence.{
    CallDetailsComponentProjection,
    CallDetailsSourceProjection,
    CallDetailsSourceRead
  }

  alias Vxpipe.Calls.{PreparedCall, VariableSnapshotHistory}

  @tenant "tenantkey1234567"
  @call "call-public-id"
  @room "room-public-id"
  @incarnation "incarnation-public-id"

  test "uses snapshotted admission, not reconfigured plan or storage" do
    # Snapshot says requested+configured, plan now says off, storage says unconfigured.
    read = read_with(facts_requested_configured(), [], plan_record_audio(false))

    assert {:ok, components} =
             CallDetailsComponentProjection.project(read, :unconfigured)

    assert status(components, "recording") == :pending
  end

  test "snapshotted opt-out stays prohibited even when plan opts in" do
    read = read_with(facts_requested(false, true), [], plan_record_audio(true))

    assert {:ok, components} =
             CallDetailsComponentProjection.project(read, :configured)

    assert status(components, "recording") == :prohibited
  end

  test "old rows without snapshot fall back to plan and storage" do
    read = read_with([room_opened_legacy()], [], plan_record_audio(false))

    assert {:ok, components} =
             CallDetailsComponentProjection.project(read, :configured)

    assert status(components, "recording") == :prohibited
  end

  test "inherited old audio stays recorded and visible" do
    artifacts = [artifact("a1", 100, :complete)]
    read = read_with([room_opened_legacy()], artifacts, plan_record_audio(:inherit))

    assert {:ok, components} =
             CallDetailsComponentProjection.project(read, :configured)

    assert status(components, "recording") == :complete

    assert {:ok, assessment} = CallDetailsSourceProjection.project(read, :configured)
    assert assessment.source.call["recording"] == "recorded"
    assert length(assessment.source.artifacts) == 1
  end

  test "inherited old audio without storage reports unconfigured" do
    artifacts = [artifact("a1", 100, :complete)]
    read = read_with([room_opened_legacy()], artifacts, plan_record_audio(:inherit))

    assert {:ok, assessment} = CallDetailsSourceProjection.project(read, :unconfigured)
    assert assessment.source.call["recording"] == "unavailable:storage_unconfigured"
    assert status(assessment.components, "recording") == :unconfigured
  end

  test "explicitly prohibited old audio stays hidden" do
    artifacts = [artifact("a1", 100, :complete)]
    read = read_with([room_opened_legacy()], artifacts, plan_record_audio(false))

    assert {:ok, components} =
             CallDetailsComponentProjection.project(read, :configured)

    assert status(components, "recording") == :failed

    assert {:ok, assessment} = CallDetailsSourceProjection.project(read, :configured)
    assert assessment.source.call["recording"] == "unavailable:prohibited_audio_present"
    assert assessment.source.artifacts == []
  end

  test "published source carries snapshotted call.recording and filters prohibited audio" do
    # Requested snapshot with no artifacts -> missing, pending component.
    read = read_with(facts_requested(true, true), [], plan_record_audio(false))

    assert {:ok, assessment} = CallDetailsSourceProjection.project(read, :unconfigured)
    assert assessment.source.call["recording"] == "unavailable:missing_recording"
    assert status(assessment.components, "recording") == :pending
    assert assessment.source.artifacts == []

    # Not requested snapshot filters artifacts even when plan opts in.
    artifacts = [artifact("a1", 100, :complete)]
    read = read_with(facts_requested(false, true), artifacts, plan_record_audio(true))

    assert {:ok, assessment} = CallDetailsSourceProjection.project(read, :configured)
    assert assessment.source.call["recording"] == "unavailable:prohibited_audio_present"
    assert assessment.source.artifacts == []
  end

  defp status(components, name) do
    components |> Enum.find(&(&1.name == name)) |> then(& &1.status)
  end

  defp read_with(facts, artifacts, plan) do
    %CallDetailsSourceRead{
      call: %PreparedCall{
        id: @call,
        tenant_key: @tenant,
        call_spec_id: "spec",
        call_spec_revision: 1,
        schema_version: "20260915.01",
        participant_routes: %{},
        entry_caller: "caller",
        entry_receiver: "assistant",
        initial_variables: %{},
        plan: plan,
        plan_digest: <<0>>,
        state: :ended,
        room_id: @room,
        created_at: ~U[2026-09-16 09:00:00Z],
        started_at: ~U[2026-09-16 09:00:01Z],
        ended_at: ~U[2026-09-16 09:01:00Z],
        incarnation_id: @incarnation,
        terminal_reason: :completed
      },
      facts: facts,
      variable_snapshots: %VariableSnapshotHistory{snapshots: [], latest: nil},
      artifacts: artifacts,
      usage_observations: [],
      usage_amounts: [],
      telephony_legs: []
    }
  end

  defp plan_record_audio(record_audio) do
    %ResolvedCallPlan{
      call_spec_id: "spec",
      call_spec_revision: 1,
      schema_version: "20260915.01",
      tenant_id: @tenant,
      actor_id: "actor",
      call_id: @call,
      room_id: @room,
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: %{record_audio: record_audio},
      participants: %{
        "caller" => %ResolvedCallPlan.Participant{
          call_spec_key: "caller",
          participant_id: "caller-runtime",
          activation_id: nil,
          kind: :human,
          description: nil,
          connection: %Vxpipe.CallEngine.CallSpec.ConnectionIntent{
            service: :web,
            mode: :receive,
            admission: :start_call
          },
          transfer_notice: nil,
          prompt: nil,
          first_message: nil,
          first_message_text: nil,
          capabilities: %ResolvedCallPlan.Capabilities{},
          while_present: nil,
          tools: %{},
          transfers: [],
          transfer_history: nil,
          variable_permissions: nil
        }
      },
      transfer_policy: nil,
      call_variables: %{sections: %{}},
      tool_visibility: nil,
      max_duration_ms: 120_000
    }
  end

  defp facts_requested_configured do
    [room_opened(%{"requested" => true, "configured" => true})]
  end

  defp facts_requested(requested, configured) do
    [room_opened(%{"requested" => requested, "configured" => configured})]
  end

  defp room_opened(recording) do
    {:ok, fact} =
      CallFact.new(
        id: "fact-1",
        kind: :room_opened,
        sequence: 1,
        tenant_key: @tenant,
        call_id: @call,
        room_id: @room,
        incarnation_id: @incarnation,
        occurred_at: ~U[2026-09-16 09:00:00Z],
        source_policy: %{"revision" => 0},
        payload: %{"recording" => recording}
      )

    fact
  end

  defp room_opened_legacy do
    {:ok, fact} =
      CallFact.new(
        id: "fact-1",
        kind: :room_opened,
        sequence: 1,
        tenant_key: @tenant,
        call_id: @call,
        room_id: @room,
        incarnation_id: @incarnation,
        occurred_at: ~U[2026-09-16 09:00:00Z],
        source_policy: %{"revision" => 0},
        payload: %{}
      )

    fact
  end

  defp artifact(id, sample_count, status) do
    {:ok, artifact} =
      CallArtifact.new(
        id: id,
        tenant_key: @tenant,
        call_id: @call,
        room_id: @room,
        incarnation_id: @incarnation,
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
