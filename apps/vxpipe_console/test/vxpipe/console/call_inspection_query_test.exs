defmodule Vxpipe.Console.CallInspectionQueryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallHistory,
    CallSummary,
    DefinitionRevision,
    Principal,
    UsageReport,
    VariableSnapshotHistory
  }

  alias Vxpipe.Console.{CallInspectionQuery, TestCallInspectionBackend}

  @tenant_key "tenantkey1234567"

  test "assembles the authorized database inspection, exact definition and usage" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_call_history: {:ok, call_history()},
        fetch_definition: {:ok, definition_revision()},
        usage_report: {:ok, %UsageReport{amounts: [], totals: []}}
      )

    assert {:ok, result} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    assert result.call == detail_page().call
    assert result.history == call_history()
    assert result.definition == {:available, definition_revision()}
    assert result.usage == {:available, %UsageReport{amounts: [], totals: []}}

    assert_receive {:inspect_call, _, "call-public-id", [limit: 1]}
    assert_receive {:fetch_call_history, _, "call-public-id", []}

    assert_receive {:fetch_definition, @tenant_key, "definition-public-id", 3, []}
    assert_receive {:usage_report, _, "call-public-id", []}
    refute_receive {:inspect_live_call, _, _, _}
  end

  test "keeps an inspectable call when supporting database records are unavailable" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_call_history: {:ok, call_history()},
        fetch_definition: {:error, :repository_unavailable},
        usage_report: {:error, :repository_unavailable}
      )

    assert {:ok, result} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    assert result.definition == {:unavailable, :repository_unavailable}
    assert result.usage == {:unavailable, :repository_unavailable}
  end

  test "requires the complete database history for a snapshot" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_call_history: {:error, :repository_unavailable}
      )

    assert {:error, :repository_unavailable} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    refute_receive {:fetch_definition, _, _, _, _}
    refute_receive {:usage_report, _, _, _}
  end

  test "does not load supporting records when the authorized call is absent" do
    backend = backend(inspect_call: {:error, :call_not_found})

    assert {:error, :call_not_found} =
             CallInspectionQuery.run(principal(), "missing-call", backend: backend)

    refute_receive {:fetch_definition, _, _, _, _}
    refute_receive {:fetch_call_history, _, _, _}
    refute_receive {:usage_report, _, _, _}
    refute_receive {:inspect_live_call, _, _, _}
  end

  defp backend(responses), do: {TestCallInspectionBackend, {self(), Map.new(responses)}}

  defp principal do
    %Principal{
      tenant_key: @tenant_key,
      api_key_id: "123e4567-e89b-42d3-a456-426614174000",
      scopes: MapSet.new([:calls])
    }
  end

  defp detail_page do
    %CallDetailPage{
      call: %CallSummary{
        id: "call-public-id",
        tenant_key: @tenant_key,
        definition_id: "definition-public-id",
        definition_revision: 3,
        state: :running,
        created_at: ~U[2026-09-16 09:00:00Z],
        started_at: ~U[2026-09-16 09:00:01Z],
        ended_at: nil,
        terminal_reason: nil,
        latest_variable_revision: 2
      },
      timeline: [],
      next_cursor: nil,
      archive_status: ArchiveStatus.from_facts([]),
      persisted_variable_revision: 2
    }
  end

  defp definition_revision do
    %DefinitionRevision{
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      revision: 3,
      schema_version: "20260915.01",
      source: %{},
      source_digest: String.duplicate("a", 64),
      compiled_metadata: %{},
      validation_errors: [],
      routes: [],
      telephony_routes: [],
      published_at: ~U[2026-09-16 08:00:00Z],
      inserted_at: ~U[2026-09-16 07:00:00Z]
    }
  end

  defp call_history do
    CallHistory.new([], %VariableSnapshotHistory{snapshots: [], latest: nil})
  end
end
