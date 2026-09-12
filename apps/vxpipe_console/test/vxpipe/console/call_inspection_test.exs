defmodule Vxpipe.Console.CallInspectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallDetailPage,
    CallListPage,
    CallSummary,
    LiveCallInspection,
    Principal,
    UsageReport
  }

  alias Vxpipe.Console.{CallInspection, TestCallInspectionBackend}

  @tenant_key "tenantkey1234567"

  test "reads list, persisted detail, and live detail through one selected backend" do
    principal = principal()
    list_page = %CallListPage{calls: [], next_cursor: nil}
    detail_page = detail_page()
    live_inspection = live_inspection()
    usage_report = %UsageReport{amounts: [], totals: []}

    backend =
      {TestCallInspectionBackend,
       {self(),
        %{
          list_calls: {:ok, list_page},
          inspect_call: {:ok, detail_page},
          inspect_live_call: {:ok, live_inspection},
          usage_report: {:ok, usage_report}
        }}}

    assert {:ok, ^list_page} =
             CallInspection.list_calls(principal, backend: backend, limit: 20)

    assert_receive {:list_calls, ^principal, [limit: 20]}

    assert {:ok, ^detail_page} =
             CallInspection.inspect_call(principal, "call-public-id",
               backend: backend,
               cursor: "persisted-cursor"
             )

    assert_receive {:inspect_call, ^principal, "call-public-id", [cursor: "persisted-cursor"]}

    assert {:ok, ^live_inspection} =
             CallInspection.inspect_live_call(principal, "call-public-id", backend: backend)

    assert_receive {:inspect_live_call, ^principal, "call-public-id", []}

    assert {:ok, ^usage_report} =
             CallInspection.usage_report(principal, "call-public-id", backend: backend)

    assert_receive {:usage_report, ^principal, "call-public-id", []}
  end

  test "fails closed when a backend returns an unexpected value" do
    backend =
      {TestCallInspectionBackend,
       {self(),
        %{
          list_calls: {:ok, %{calls: []}},
          inspect_call: :unexpected,
          inspect_live_call: {:error, :call_not_live},
          usage_report: {:ok, %{amounts: []}}
        }}}

    assert {:error, :invalid_inspection_response} =
             CallInspection.list_calls(principal(), backend: backend)

    assert {:error, :invalid_inspection_response} =
             CallInspection.inspect_call(principal(), "call-public-id", backend: backend)

    assert {:error, :call_not_live} =
             CallInspection.inspect_live_call(principal(), "call-public-id", backend: backend)

    assert {:error, :invalid_inspection_response} =
             CallInspection.usage_report(principal(), "call-public-id", backend: backend)
  end

  defp principal do
    %Principal{
      tenant_key: @tenant_key,
      api_key_id: "01234567-89ab-4cde-8fab-0123456789ab",
      scopes: MapSet.new([:calls])
    }
  end

  defp detail_page do
    %CallDetailPage{
      call: call_summary(),
      timeline: [],
      next_cursor: nil,
      archive_status: ArchiveStatus.from_facts([]),
      persisted_variable_revision: nil
    }
  end

  defp live_inspection do
    %LiveCallInspection{
      tenant_key: @tenant_key,
      call_id: "call-public-id",
      room_id: "room-public-id",
      incarnation_id: "incarnation-public-id",
      timeline: [],
      latest_fact_sequence: nil,
      live_variable_revision: nil,
      dropped_records: 0,
      rejected_records: 0
    }
  end

  defp call_summary do
    %CallSummary{
      id: "call-public-id",
      tenant_key: @tenant_key,
      definition_id: "definition-public-id",
      definition_revision: 1,
      state: :running,
      created_at: ~U[2026-09-09 16:30:00Z],
      started_at: ~U[2026-09-09 16:30:01Z],
      ended_at: nil,
      terminal_reason: nil,
      latest_variable_revision: nil
    }
  end
end
