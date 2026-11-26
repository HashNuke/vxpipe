defmodule Vxpipe.Console.CallInspectionRecordingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    CallFact,
    CallHistory,
    CallSummary,
    PreparedCall,
    UsageReport,
    VariableSnapshotHistory
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.Console.{CallInspectionPresenter, CallInspectionResult}

  @tenant "tenantkey1234567"

  test "presents snapshotted requested recording as recorded" do
    result =
      result_with(facts_requested(true, true), [artifact("a1", 320, :complete)], plan(false))

    response = CallInspectionPresenter.present(result)

    assert response["call"]["recording"] == "recorded"
  end

  test "presents snapshotted opt-out as not_requested even when plan opts in" do
    result = result_with(facts_requested(false, true), [], plan(true))

    response = CallInspectionPresenter.present(result)

    assert response["call"]["recording"] == "not_requested"
  end

  test "presents storage_unconfigured as unavailable" do
    result = result_with(facts_requested(true, false), [], plan(true))

    response = CallInspectionPresenter.present(result)

    assert response["call"]["recording"] == "unavailable:storage_unconfigured"
  end

  test "presents missing recording as unavailable when requested but absent" do
    result = result_with(facts_requested(true, true), [], plan(true))

    response = CallInspectionPresenter.present(result)

    assert response["call"]["recording"] == "unavailable:missing_recording"
  end

  test "old rows without snapshot fall back to plan" do
    result = result_with([legacy_room_opened()], [], plan(false))

    assert CallInspectionPresenter.present(result)["call"]["recording"] == "not_requested"
  end

  test "inherited old audio with readable evidence is recorded" do
    result =
      result_with([legacy_room_opened()], [artifact("a1", 100, :complete)], plan(:inherit))

    assert CallInspectionPresenter.present(result)["call"]["recording"] == "recorded"
  end

  test "explicitly prohibited old audio stays unavailable" do
    result =
      result_with([legacy_room_opened()], [artifact("a1", 100, :complete)], plan(false))

    assert CallInspectionPresenter.present(result)["call"]["recording"] ==
             "unavailable:prohibited_audio_present"
  end

  defp result_with(facts, artifacts, resolved_plan) do
    history = CallHistory.new(facts, %VariableSnapshotHistory{snapshots: [], latest: nil})

    %CallInspectionResult{
      call: %CallSummary{
        id: "call-public-id",
        tenant_key: @tenant,
        call_spec_id: "spec",
        call_spec_revision: 1,
        state: :ended,
        created_at: ~U[2026-09-16 09:00:00Z],
        started_at: ~U[2026-09-16 09:00:01Z],
        ended_at: ~U[2026-09-16 09:01:00Z],
        terminal_reason: :completed,
        latest_variable_revision: 0
      },
      prepared_call: %PreparedCall{
        id: "call-public-id",
        tenant_key: @tenant,
        call_spec_id: "spec",
        call_spec_revision: 1,
        schema_version: "20260915.01",
        participant_routes: %{},
        entry_caller: "caller",
        entry_receiver: "assistant",
        initial_variables: %{},
        plan: resolved_plan,
        plan_digest: <<0>>,
        state: :ended,
        room_id: "room-public-id",
        created_at: ~U[2026-09-16 09:00:00Z],
        started_at: ~U[2026-09-16 09:00:01Z],
        ended_at: ~U[2026-09-16 09:01:00Z],
        incarnation_id: "incarnation-public-id",
        terminal_reason: :completed
      },
      history: history,
      usage: {:available, %UsageReport{amounts: [], totals: []}},
      artifacts: artifacts
    }
  end

  defp plan(record_audio) do
    %ResolvedCallPlan{
      call_spec_id: "spec",
      call_spec_revision: 1,
      schema_version: "20260915.01",
      tenant_id: @tenant,
      actor_id: "actor",
      call_id: "call-public-id",
      room_id: "room-public-id",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: %{record_audio: record_audio},
      participants: %{},
      transfer_policy: nil,
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 120_000
    }
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
        call_id: "call-public-id",
        room_id: "room-public-id",
        incarnation_id: "incarnation-public-id",
        occurred_at: ~U[2026-09-16 09:00:00Z],
        source_policy: %{"revision" => 0},
        payload: %{"recording" => recording}
      )

    fact
  end

  defp legacy_room_opened do
    {:ok, fact} =
      CallFact.new(
        id: "fact-1",
        kind: :room_opened,
        sequence: 1,
        tenant_key: @tenant,
        call_id: "call-public-id",
        room_id: "room-public-id",
        incarnation_id: "incarnation-public-id",
        occurred_at: ~U[2026-09-16 09:00:00Z],
        source_policy: %{"revision" => 0},
        payload: %{}
      )

    fact
  end

  defp artifact(id, sample_count, status) do
    {:ok, artifact} =
      Vxpipe.Calls.CallArtifact.new(
        id: id,
        tenant_key: @tenant,
        call_id: "call-public-id",
        room_id: "room-public-id",
        incarnation_id: "incarnation-public-id",
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
