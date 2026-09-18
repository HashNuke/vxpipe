defmodule Vxpipe.Console.CallInspectionQueryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallHistory,
    CallSummary,
    PreparedCall,
    Principal,
    UsageReport,
    VariableSnapshotHistory
  }

  alias Vxpipe.Console.{CallInspectionQuery, TestCallInspectionBackend}

  @tenant_key "tenantkey1234567"

  test "assembles the authorized database inspection, resolved plan, history and usage" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_prepared_call: {:ok, prepared_call()},
        fetch_call_history: {:ok, call_history()},
        usage_report: {:ok, %UsageReport{amounts: [], totals: []}}
      )

    assert {:ok, result} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    assert result.call == detail_page().call
    assert result.prepared_call == prepared_call()
    assert result.history == call_history()
    assert result.usage == {:available, %UsageReport{amounts: [], totals: []}}

    assert_receive {:inspect_call, _, "call-public-id", [limit: 1]}
    assert_receive {:fetch_prepared_call, @tenant_key, "call-public-id", []}
    assert_receive {:fetch_call_history, _, "call-public-id", []}
    assert_receive {:usage_report, _, "call-public-id", []}
    refute_receive {:inspect_live_call, _, _, _}
  end

  test "keeps an inspectable call when persisted usage is unavailable" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_prepared_call: {:ok, prepared_call()},
        fetch_call_history: {:ok, call_history()},
        usage_report: {:error, :repository_unavailable}
      )

    assert {:ok, result} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    assert result.usage == {:unavailable, :repository_unavailable}
  end

  test "requires the immutable prepared call and resolved participant plan" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_prepared_call: {:error, :repository_unavailable}
      )

    assert {:error, :repository_unavailable} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    refute_receive {:fetch_call_history, _, _, _}
    refute_receive {:usage_report, _, _, _}
  end

  test "requires the complete database history for a snapshot" do
    backend =
      backend(
        inspect_call: {:ok, detail_page()},
        fetch_prepared_call: {:ok, prepared_call()},
        fetch_call_history: {:error, :repository_unavailable}
      )

    assert {:error, :repository_unavailable} =
             CallInspectionQuery.run(principal(), "call-public-id", backend: backend)

    refute_receive {:usage_report, _, _, _}
  end

  test "does not load supporting records when the authorized call is absent" do
    backend = backend(inspect_call: {:error, :call_not_found})

    assert {:error, :call_not_found} =
             CallInspectionQuery.run(principal(), "missing-call", backend: backend)

    refute_receive {:fetch_prepared_call, _, _, _}
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
        call_spec_id: "call-spec-public-id",
        call_spec_revision: 3,
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

  defp call_history do
    CallHistory.new([], %VariableSnapshotHistory{snapshots: [], latest: nil})
  end

  defp prepared_call do
    %PreparedCall{
      id: "call-public-id",
      tenant_key: @tenant_key,
      call_spec_id: "call-spec-public-id",
      call_spec_revision: 3,
      schema_version: "20260915.01",
      participant_routes: %{},
      entry_caller: "caller",
      entry_receiver: "assistant",
      initial_variables: %{},
      plan: :resolved_plan,
      plan_digest: <<0>>,
      state: :running,
      room_id: "room-public-id",
      created_at: ~U[2026-09-16 09:00:00Z],
      started_at: ~U[2026-09-16 09:00:01Z],
      ended_at: nil,
      incarnation_id: "incarnation-public-id",
      terminal_reason: nil
    }
  end
end
