defmodule Vxpipe.Console.CallInspectionPresentationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallSummary,
    CallTimelineEntry,
    LiveCallInspection
  }

  alias Vxpipe.Console.{CallInspectionTimeline, CallVariableDiff}

  test "combines live and persisted entries without erasing their source identity" do
    persisted_entry = timeline_entry(:persisted, "shared-event", 1)
    live_entry = timeline_entry(:live, "shared-event", 2)

    timeline =
      CallInspectionTimeline.combine(
        persisted_detail([persisted_entry]),
        live_detail([live_entry])
      )

    assert Enum.map(timeline, &CallInspectionTimeline.selection_key/1) == [
             "live:shared-event",
             "persisted:shared-event"
           ]

    assert CallInspectionTimeline.select(timeline, "persisted:shared-event") == persisted_entry
  end

  test "orders out-of-order evidence by source time and deduplicates one source identity" do
    older = timeline_entry(:persisted, "older-event", 1)

    newer = %{
      timeline_entry(:persisted, "newer-event", 3)
      | occurred_at: ~U[2026-09-09 16:30:07Z]
    }

    duplicate = %{newer | payload: %{"text" => "duplicate receipt"}}

    timeline =
      CallInspectionTimeline.combine(
        persisted_detail([newer, older, duplicate]),
        nil
      )

    assert Enum.map(timeline, &CallInspectionTimeline.selection_key/1) == [
             "persisted:newer-event",
             "persisted:older-event"
           ]

    assert hd(timeline).payload == %{"text" => "hello"}
  end

  test "reports only permitted field changes between persisted and live snapshots" do
    persisted_snapshot =
      variable_snapshot(:persisted, "persisted-r2", 2, %{
        "order" => %{
          "revision" => 2,
          "value" => %{"postal_code" => "12345", "status" => "pending"}
        }
      })

    live_snapshot =
      variable_snapshot(:live, "live-r3", 3, %{
        "order" => %{
          "revision" => 3,
          "value" => %{"postal_code" => "12345", "status" => "confirmed"}
        }
      })

    assert {:ok, diff} =
             CallVariableDiff.between(
               persisted_detail([persisted_snapshot]),
               live_detail([live_snapshot])
             )

    assert diff.from_revision == 2
    assert diff.to_revision == 3

    assert diff.changes == %{
             "order" => %{
               "status" => %{"before" => "pending", "after" => "confirmed"}
             }
           }
  end

  defp persisted_detail(timeline) do
    %CallDetailPage{
      call: call_summary(),
      timeline: timeline,
      next_cursor: nil,
      archive_status: ArchiveStatus.from_facts([]),
      persisted_variable_revision: 2
    }
  end

  defp live_detail(timeline) do
    %LiveCallInspection{
      tenant_key: "tenant-key",
      call_id: "call-id",
      room_id: "room-id",
      incarnation_id: "incarnation-id",
      timeline: timeline,
      latest_fact_sequence: 2,
      live_variable_revision: 3,
      dropped_records: 0,
      rejected_records: 0
    }
  end

  defp call_summary do
    %CallSummary{
      id: "call-id",
      tenant_key: "tenant-key",
      definition_id: "definition-id",
      definition_revision: 1,
      state: :running,
      created_at: ~U[2026-09-09 16:30:00Z],
      started_at: ~U[2026-09-09 16:30:01Z],
      ended_at: nil,
      terminal_reason: nil,
      latest_variable_revision: 2
    }
  end

  defp timeline_entry(source, id, sequence) do
    entry(source, id,
      kind: :accepted_input,
      source_sequence: sequence,
      variable_revision: nil,
      section_revision: nil,
      payload: %{"text" => "hello"}
    )
  end

  defp variable_snapshot(source, id, revision, payload) do
    entry(source, id,
      kind: :variable_snapshot,
      source_sequence: nil,
      variable_revision: revision,
      section_revision: revision,
      payload: payload
    )
  end

  defp entry(source, id, options) do
    %CallTimelineEntry{
      id: id,
      kind: Keyword.fetch!(options, :kind),
      source: source,
      source_sequence: Keyword.fetch!(options, :source_sequence),
      occurred_at: ~U[2026-09-09 16:30:05Z],
      participant_id: "participant-id",
      activation_id: "activation-id",
      source_participant_id: "source-participant-id",
      connection_id: nil,
      command_id: "command-id",
      correlation_id: "turn-id",
      tool_call_id: nil,
      variable_revision: Keyword.fetch!(options, :variable_revision),
      section_revision: Keyword.fetch!(options, :section_revision),
      payload: Keyword.fetch!(options, :payload),
      observed_duration_ms: nil,
      duration_basis: nil
    }
  end
end
