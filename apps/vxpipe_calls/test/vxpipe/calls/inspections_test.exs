defmodule Vxpipe.Calls.InspectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    CallFact,
    CallSummary,
    InstallationOperator,
    Principal,
    TestInspectionRepository,
    VariableSnapshot
  }

  test "installation operator scopes call inspection to the requested tenant" do
    call = summary("call-a1", "AAAAAAAAAAAAAAAA", ~U[2026-09-09 12:00:00.000000Z])
    repository = start_supervised!({TestInspectionRepository, calls: [call]})
    options = [inspection_repository: TestInspectionRepository.repository(repository)]

    assert {:ok, access} =
             Calls.operator_call_access(InstallationOperator.authority(), call.tenant_key)

    assert {:ok, detail} = Calls.inspect_call(access, call.id, options)
    assert detail.call == call

    assert {:ok, other_access} =
             Calls.operator_call_access(InstallationOperator.authority(), "BBBBBBBBBBBBBBBB")

    assert {:error, :call_not_found} = Calls.inspect_call(other_access, call.id, options)
  end

  test "rejects an invalid call-read authority without raising" do
    assert {:error, :invalid_call_inspection_request} =
             Calls.inspect_call(nil, "call-public-id", [])
  end

  test "lists a bounded tenant page and continues with an opaque cursor" do
    repository =
      start_supervised!(
        {TestInspectionRepository,
         calls: [
           summary("call-a1", "AAAAAAAAAAAAAAAA", ~U[2026-09-09 12:00:00.000000Z]),
           summary("call-b1", "BBBBBBBBBBBBBBBB", ~U[2026-09-09 12:30:00.000000Z]),
           summary("call-a2", "AAAAAAAAAAAAAAAA", ~U[2026-09-09 13:00:00.000000Z]),
           summary("call-a3", "AAAAAAAAAAAAAAAA", ~U[2026-09-09 14:00:00.000000Z])
         ]}
      )

    options = [inspection_repository: TestInspectionRepository.repository(repository), limit: 2]
    principal = principal("AAAAAAAAAAAAAAAA")

    assert {:ok, first_page} = Calls.list_calls(principal, options)
    assert Enum.map(first_page.calls, & &1.id) == ["call-a3", "call-a2"]
    assert is_binary(first_page.next_cursor)
    refute first_page.next_cursor =~ "call-a2"

    assert {:ok, second_page} =
             Calls.list_calls(principal, Keyword.put(options, :cursor, first_page.next_cursor))

    assert Enum.map(second_page.calls, & &1.id) == ["call-a1"]
    assert second_page.next_cursor == nil

    assert TestInspectionRepository.operations(repository) == [
             {:list_calls, "AAAAAAAAAAAAAAAA", 3, nil},
             {:list_calls, "AAAAAAAAAAAAAAAA", 3, {~U[2026-09-09 13:00:00.000000Z], "call-a2"}}
           ]
  end

  test "rejects unauthorized and malformed list requests before repository access" do
    repository = start_supervised!(TestInspectionRepository)
    repository_option = [inspection_repository: TestInspectionRepository.repository(repository)]

    unauthorized = %{principal("AAAAAAAAAAAAAAAA") | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} = Calls.list_calls(unauthorized, repository_option)

    assert {:error, :invalid_call_list_request} =
             Calls.list_calls(principal("AAAAAAAAAAAAAAAA"),
               inspection_repository: TestInspectionRepository.repository(repository),
               limit: 101
             )

    assert {:error, :invalid_cursor} =
             Calls.list_calls(principal("AAAAAAAAAAAAAAAA"),
               inspection_repository: TestInspectionRepository.repository(repository),
               cursor: "forged-or-corrupt"
             )

    assert TestInspectionRepository.operations(repository) == []
  end

  test "pages correlated persisted history for one authorized call" do
    call = summary("call-a1", "AAAAAAAAAAAAAAAA", ~U[2026-09-09 12:00:00.000000Z])
    started = fact(:tool_call_started, 1, ~U[2026-09-09 12:00:01.000000Z])
    snapshot = snapshot(~U[2026-09-09 12:00:02.000000Z])
    completed = fact(:tool_call_completed, 2, ~U[2026-09-09 12:00:04.000000Z])

    repository =
      start_supervised!(
        {TestInspectionRepository,
         calls: [call], history: %{{call.tenant_key, call.id} => [started, snapshot, completed]}}
      )

    options = [inspection_repository: TestInspectionRepository.repository(repository), limit: 2]
    principal = principal(call.tenant_key)

    assert {:ok, first_page} = Calls.inspect_call(principal, call.id, options)
    assert first_page.call == call
    assert first_page.archive_status.state == :unconfirmed
    assert first_page.persisted_variable_revision == 1
    assert Enum.map(first_page.timeline, & &1.kind) == [:tool_call_completed, :variable_snapshot]
    assert hd(first_page.timeline).observed_duration_ms == nil
    assert is_binary(first_page.next_cursor)

    assert {:ok, second_page} =
             Calls.inspect_call(
               principal,
               call.id,
               Keyword.put(options, :cursor, first_page.next_cursor)
             )

    assert Enum.map(second_page.timeline, & &1.kind) == [:tool_call_started]
    assert second_page.next_cursor == nil

    assert TestInspectionRepository.operations(repository) == [
             {:fetch_call, call.tenant_key, call.id},
             {:fetch_archive_status, call.tenant_key, call.id},
             {:list_history, call.tenant_key, call.id, 3, nil},
             {:fetch_call, call.tenant_key, call.id},
             {:fetch_archive_status, call.tenant_key, call.id},
             {:list_history, call.tenant_key, call.id, 3,
              {snapshot.occurred_at, 1, snapshot.global_revision, snapshot.id}}
           ]
  end

  test "does not disclose call detail across tenant or scope boundaries" do
    call = summary("call-a1", "AAAAAAAAAAAAAAAA", ~U[2026-09-09 12:00:00.000000Z])
    repository = start_supervised!({TestInspectionRepository, calls: [call]})
    options = [inspection_repository: TestInspectionRepository.repository(repository)]

    assert {:error, :call_not_found} =
             Calls.inspect_call(principal("BBBBBBBBBBBBBBBB"), call.id, options)

    unauthorized = %{principal(call.tenant_key) | scopes: MapSet.new([:admin])}
    assert {:error, :insufficient_scope} = Calls.inspect_call(unauthorized, call.id, options)

    assert {:error, :invalid_cursor} =
             Calls.inspect_call(principal(call.tenant_key), call.id,
               inspection_repository: TestInspectionRepository.repository(repository),
               cursor: "invalid"
             )

    assert TestInspectionRepository.operations(repository) == [
             {:fetch_call, "BBBBBBBBBBBBBBBB", call.id}
           ]
  end

  defp principal(tenant_key) do
    %Principal{
      tenant_key: tenant_key,
      api_key_id: "key-calls",
      scopes: MapSet.new([:calls])
    }
  end

  defp summary(id, tenant_key, created_at) do
    %CallSummary{
      id: id,
      tenant_key: tenant_key,
      call_spec_id: "call-spec-1",
      call_spec_revision: 1,
      state: :running,
      created_at: created_at,
      started_at: DateTime.add(created_at, 1, :second),
      ended_at: nil,
      terminal_reason: nil,
      latest_variable_revision: 1
    }
  end

  defp fact(kind, sequence, occurred_at) do
    payload =
      case kind do
        :tool_call_started -> %{"arguments" => %{}, "name" => "slow_lookup"}
        :tool_call_completed -> %{"name" => "slow_lookup", "result" => %{"ok" => true}}
      end

    assert {:ok, fact} =
             CallFact.new(
               id: "fact-#{sequence}",
               kind: kind,
               sequence: sequence,
               tenant_key: "AAAAAAAAAAAAAAAA",
               call_id: "call-a1",
               room_id: "room-a1",
               incarnation_id: "rinc-a1",
               participant_id: "assistant-1",
               activation_id: "activation-1",
               source_participant_id: "caller-1",
               command_id: "command-1",
               correlation_id: "turn-1",
               tool_call_id: "tool-1",
               occurred_at: occurred_at,
               source_policy: %{"revision" => 0},
               payload: payload
             )

    fact
  end

  defp snapshot(occurred_at) do
    assert {:ok, snapshot} =
             VariableSnapshot.new(
               id: "snapshot-1",
               kind: :update,
               tenant_key: "AAAAAAAAAAAAAAAA",
               call_id: "call-a1",
               room_id: "room-a1",
               incarnation_id: "rinc-a1",
               global_revision: 1,
               sections: %{"order" => %{revision: 1, value: %{"status" => "ready"}}},
               source_policy: %{"revision" => 0},
               command_id: "command-1",
               participant_id: "assistant-1",
               activation_id: "activation-1",
               source_participant_id: "caller-1",
               correlation_id: "turn-1",
               tool_call_id: "tool-1",
               section: "order",
               section_revision: 1,
               occurred_at: occurred_at
             )

    snapshot
  end
end
