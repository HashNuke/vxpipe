defmodule Vxpipe.CallEngine.RoomRecordingSnapshotTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.Room.Snapshot

  test "snapshots requested recording and storage capability upon admission" do
    plan = %{resolved_plan() | media_policy: %{record_audio: true}}

    snapshot =
      Snapshot.new(plan, "incarnation-1", start_command_id: "cmd-1", recording: [enabled: true])

    assert snapshot.record_audio_requested == true
    assert snapshot.recording_configured == true
  end

  test "snapshots opt-out and unconfigured storage" do
    plan = %{resolved_plan() | media_policy: %{record_audio: false}}

    snapshot =
      Snapshot.new(plan, "incarnation-1", start_command_id: "cmd-1", recording: [enabled: false])

    assert snapshot.record_audio_requested == false
    assert snapshot.recording_configured == false
  end

  test "legacy room without plan records no request" do
    command = %CreateRoom{
      id: "cmd-1",
      tenant_id: "tenant-1",
      room_id: "room-1",
      actor_id: "actor-1",
      agent: nil,
      agent_participant_id: nil,
      deadline: ~U[2026-09-16 09:00:00Z]
    }

    snapshot = Snapshot.new(command, "incarnation-1", [])

    assert snapshot.record_audio_requested == false
    assert snapshot.recording_configured == false
  end

  defp resolved_plan do
    %ResolvedCallPlan{
      call_spec_id: "spec",
      call_spec_revision: 1,
      schema_version: "20260915.01",
      tenant_id: "tenant-1",
      actor_id: "actor-1",
      call_id: "call-1",
      room_id: "room-1",
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      media_policy: %{record_audio: false},
      participants: %{},
      transfer_policy: nil,
      call_variables: nil,
      tool_visibility: nil,
      max_duration_ms: 120_000
    }
  end
end
