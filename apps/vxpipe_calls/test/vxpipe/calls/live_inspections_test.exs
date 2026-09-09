defmodule Vxpipe.Calls.LiveInspectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Fact, as: EngineFact
  alias Vxpipe.CallEngine.CallVariables.UpdateSnapshot, as: EngineVariableSnapshot
  alias Vxpipe.CallEngine.LiveInspection.{Buffer, Port}
  alias Vxpipe.CallEngine.LiveInspection.Snapshot, as: EngineSnapshot
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Principal, TestLiveInspectionSource}

  test "authorizes and translates a correlated live timeline without leaking engine records" do
    source = start_supervised!({TestLiveInspectionSource, snapshot: engine_snapshot()})
    options = [live_inspection_source: TestLiveInspectionSource.source(source)]

    assert {:ok, inspection} =
             Calls.inspect_live_call(principal("tenant-live"), "call-live", options)

    assert inspection.tenant_key == "tenant-live"
    assert inspection.call_id == "call-live"
    assert inspection.room_id == "room-live"
    assert inspection.incarnation_id == "rinc-live"
    assert inspection.latest_fact_sequence == 2
    assert inspection.live_variable_revision == 1
    assert inspection.dropped_records == 3
    assert inspection.rejected_records == 2

    assert Enum.map(inspection.timeline, &{&1.kind, &1.source}) == [
             {:tool_call_completed, :live},
             {:variable_snapshot, :live},
             {:tool_call_started, :live}
           ]

    assert hd(inspection.timeline).observed_duration_ms == 3_000
    assert hd(inspection.timeline).duration_basis == :source_timestamps
    refute inspect(inspection) =~ "private-live-result"

    assert TestLiveInspectionSource.operations(source) == [
             {:fetch, "tenant-live", "call-live"}
           ]
  end

  test "rejects missing scope, malformed IDs, and cross-tenant live reads before disclosure" do
    source = start_supervised!({TestLiveInspectionSource, snapshot: engine_snapshot()})
    options = [live_inspection_source: TestLiveInspectionSource.source(source)]
    unauthorized = %{principal("tenant-live") | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Calls.inspect_live_call(unauthorized, "call-live", options)

    assert {:error, :invalid_call_inspection_request} =
             Calls.inspect_live_call(principal("tenant-live"), "", options)

    assert {:error, :call_not_live} =
             Calls.inspect_live_call(principal("tenant-other"), "call-live", options)

    assert TestLiveInspectionSource.operations(source) == [
             {:fetch, "tenant-other", "call-live"}
           ]
  end

  test "rejects a source snapshot containing a record from another call identity" do
    snapshot = engine_snapshot()
    [first | rest] = snapshot.records
    mismatched = %{snapshot | records: [%{first | tenant_id: "tenant-other"} | rest]}
    source = start_supervised!({TestLiveInspectionSource, snapshot: mismatched})

    assert {:error, :invalid_live_inspection} =
             Calls.inspect_live_call(principal("tenant-live"), "call-live",
               live_inspection_source: TestLiveInspectionSource.source(source)
             )

    assert TestLiveInspectionSource.operations(source) == [
             {:fetch, "tenant-live", "call-live"}
           ]
  end

  test "uses the configured engine source without exposing the engine buffer" do
    identity = %{
      tenant_id: "tenant-live",
      call_id: "call-live",
      room_id: "room-live",
      incarnation_id: "rinc-live-source"
    }

    buffer =
      start_supervised!(
        {Buffer, identity: identity, maximum_pending_records: 4, maximum_retained_records: 4}
      )

    assert {:ok, port} = Buffer.port(buffer)
    fact = %{engine_fact(:tool_call_started, 1, ~U[2026-09-09 16:00:01.000000Z]) |
      incarnation_id: identity.incarnation_id
    }

    assert :ok = Port.offer(port, fact)
    assert {:ok, inspection} = Calls.inspect_live_call(principal("tenant-live"), "call-live")
    assert [%{kind: :tool_call_started, source: :live}] = inspection.timeline
    refute Map.has_key?(inspection, :records)
  end

  defp engine_snapshot do
    %EngineSnapshot{
      tenant_id: "tenant-live",
      call_id: "call-live",
      room_id: "room-live",
      incarnation_id: "rinc-live",
      records: [
        engine_fact(:tool_call_started, 1, ~U[2026-09-09 16:00:01.000000Z]),
        engine_variable_snapshot(),
        engine_fact(:tool_call_completed, 2, ~U[2026-09-09 16:00:04.000000Z])
      ],
      latest_fact_sequence: 2,
      latest_variable_revision: 1,
      dropped_records: 3,
      rejected_records: 2
    }
  end

  defp engine_fact(kind, sequence, occurred_at) do
    payload =
      case kind do
        :tool_call_started -> %{"arguments" => %{}, "name" => "slow_lookup"}

        :tool_call_completed ->
          %{"name" => "slow_lookup", "result" => %{"value" => "private-live-result"}}
      end

    EngineFact.new!(
      id: "live-fact-#{sequence}",
      kind: kind,
      sequence: sequence,
      tenant_id: "tenant-live",
      call_id: "call-live",
      room_id: "room-live",
      incarnation_id: "rinc-live",
      participant_id: "assistant-live",
      activation_id: "activation-live",
      source_participant_id: "caller-live",
      command_id: "command-live",
      correlation_id: "turn-live",
      tool_call_id: "tool-live",
      occurred_at: occurred_at,
      source_policy: %{"revision" => 0},
      payload: payload
    )
  end

  defp engine_variable_snapshot do
    %EngineVariableSnapshot{
      id: "live-variable-1",
      command_id: "command-live",
      tenant_id: "tenant-live",
      call_id: "call-live",
      room_id: "room-live",
      incarnation_id: "rinc-live",
      participant_id: "assistant-live",
      activation_id: "activation-live",
      source_participant_id: "caller-live",
      correlation_id: "turn-live",
      tool_call_id: "tool-live",
      section: "intake",
      section_revision: 1,
      global_revision: 1,
      sections: %{
        "intake" => %{revision: 1, value: %{"summary" => "private-live-result"}}
      },
      source_policy: %{"revision" => 0},
      occurred_at: ~U[2026-09-09 16:00:02.000000Z]
    }
  end

  defp principal(tenant_key) do
    %Principal{
      tenant_key: tenant_key,
      api_key_id: "key-live-inspection",
      scopes: MapSet.new([:calls])
    }
  end
end
