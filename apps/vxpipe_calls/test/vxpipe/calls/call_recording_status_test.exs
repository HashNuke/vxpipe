defmodule Vxpipe.Calls.CallRecordingStatusTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{CallArtifact, CallFact, CallRecordingStatus}

  @tenant "tenantkey1234567"
  @call "call-public-id"
  @room "room-public-id"
  @incarnation "incarnation-public-id"

  test "snapshotted opt-in with storage records status and does not reinterpret reconfiguration" do
    facts = [room_opened(%{"requested" => true, "configured" => true})]
    artifacts = [artifact("a1", 320, :complete)]

    assert CallRecordingStatus.status(facts, artifacts,
             fallback_requested: false,
             fallback_configured: false
           ) == "recorded"

    # Reconfiguration (plan off, storage off) must not reinterpret snapshot.
    assert CallRecordingStatus.status(facts, artifacts,
             fallback_requested: false,
             fallback_configured: false
           ) == "recorded"
  end

  test "snapshotted opt-out reports not_requested even when plan later opts in" do
    facts = [room_opened(%{"requested" => false, "configured" => true})]

    assert CallRecordingStatus.status(facts, [], fallback_requested: true) == "not_requested"
  end

  test "snapshotted storage_unconfigured reports unavailable" do
    facts = [room_opened(%{"requested" => true, "configured" => false})]

    assert CallRecordingStatus.status(facts, [], fallback_requested: true) ==
             "unavailable:storage_unconfigured"
  end

  test "snapshotted requested with missing artifacts reports missing" do
    facts = [room_opened(%{"requested" => true, "configured" => true})]

    assert CallRecordingStatus.status(facts, [], fallback_requested: true) ==
             "unavailable:missing_recording"
  end

  test "snapshotted requested with incomplete artifacts stays playable with honest completeness" do
    facts = [room_opened(%{"requested" => true, "configured" => true})]
    artifacts = [artifact("a1", 320, :incomplete)]

    assert CallRecordingStatus.status(facts, artifacts, fallback_requested: true) ==
             "recorded"

    assert {status, details} =
             CallRecordingStatus.component_decision(facts, artifacts, fallback_requested: true)

    assert status == :failed
    assert details["reason"] == "incomplete_recording"
    assert details["artifact_count"] == 1
    assert details["incomplete_artifact_count"] == 1
  end

  test "gapped but complete artifacts stay playable" do
    facts = [room_opened(%{"requested" => true, "configured" => true})]
    artifacts = [gapped_artifact("a1", 320)]

    assert CallRecordingStatus.status(facts, artifacts, fallback_requested: true) == "recorded"

    assert {:complete, %{"artifact_count" => 1}} =
             CallRecordingStatus.component_decision(facts, artifacts, fallback_requested: true)
  end

  test "terminal writer failures retain accepted sample evidence even without an object" do
    artifacts = [%{artifact("a1", 320, :incomplete) | object_reference: nil}]

    for facts <- [[], [room_opened(%{"requested" => false, "configured" => true})]] do
      assert {:failed, %{"reason" => "prohibited_audio_present"}} =
               CallRecordingStatus.component_decision(facts, artifacts, fallback_requested: false)
    end

    facts = [room_opened(%{"requested" => true, "configured" => true})]

    assert {:failed, %{"reason" => "incomplete_recording"}} =
             CallRecordingStatus.component_decision(facts, artifacts)

    assert CallRecordingStatus.status(facts, artifacts) == "unavailable:missing_recording"
  end

  test "all zero samples are not recorded" do
    facts = [room_opened(%{"requested" => true, "configured" => true})]
    artifacts = [artifact("a1", 0, :complete), artifact("a2", 0, :incomplete)]

    assert CallRecordingStatus.status(facts, artifacts, fallback_requested: true) ==
             "unavailable:missing_recording"
  end

  test "old rows without snapshot fall back to plan and current storage" do
    facts = [room_opened(nil)]

    assert CallRecordingStatus.status(facts, [], fallback_requested: false) == "not_requested"
  end

  test "inherited old audio with readable evidence stays recorded" do
    facts = [room_opened(nil)]
    artifacts = [artifact("a1", 100, :complete)]

    assert CallRecordingStatus.status(facts, artifacts, fallback_requested: :inherit) ==
             "recorded"
  end

  test "explicitly prohibited old audio stays unavailable" do
    facts = [room_opened(nil)]
    artifacts = [artifact("a1", 100, :complete)]

    assert CallRecordingStatus.status(facts, artifacts, fallback_requested: false) ==
             "unavailable:prohibited_audio_present"
  end

  test "inherited old audio without storage reports unconfigured" do
    facts = [room_opened(nil)]
    artifacts = [artifact("a1", 100, :complete)]

    assert CallRecordingStatus.status(facts, artifacts,
             fallback_requested: :inherit,
             fallback_configured: false
           ) == "unavailable:storage_unconfigured"
  end

  test "snapshotted opt-out with audio stays prohibited" do
    facts = [room_opened(%{"requested" => false, "configured" => true})]
    artifacts = [artifact("a1", 100, :complete)]

    assert CallRecordingStatus.status(facts, artifacts, fallback_requested: true) ==
             "unavailable:prohibited_audio_present"
  end

  defp room_opened(nil) do
    fact(1, :room_opened, %{})
  end

  defp room_opened(recording) when is_map(recording) do
    fact(1, :room_opened, %{"recording" => recording})
  end

  defp fact(sequence, kind, payload) do
    {:ok, fact} =
      CallFact.new(
        id: "fact-#{sequence}",
        kind: kind,
        sequence: sequence,
        tenant_key: @tenant,
        call_id: @call,
        room_id: @room,
        incarnation_id: @incarnation,
        occurred_at: ~U[2026-09-16 09:00:00Z],
        source_policy: %{"revision" => 0},
        payload: payload
      )

    fact
  end

  defp artifact(id, sample_count, status) do
    {started, ended} =
      if sample_count > 0, do: {0, max(sample_count, 1)}, else: {nil, nil}

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
        started_offset_samples: started,
        ended_offset_samples: ended,
        sample_count: sample_count,
        accepted_chunks: 1,
        rejected_chunks: 0,
        gaps: [],
        status: status,
        terminal_reason: "normal"
      )

    artifact
  end

  defp gapped_artifact(id, sample_count) do
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
        ended_offset_samples: sample_count + 160,
        sample_count: sample_count,
        accepted_chunks: 2,
        rejected_chunks: 0,
        gaps: [%{"offset_samples" => 160, "sample_count" => 160}],
        status: :complete,
        terminal_reason: "normal"
      )

    artifact
  end
end
