defmodule Vxpipe.Calls.InspectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallSummary, Principal, TestInspectionRepository}

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
      definition_id: "definition-1",
      definition_revision: 1,
      state: :running,
      created_at: created_at,
      started_at: DateTime.add(created_at, 1, :second),
      ended_at: nil,
      terminal_reason: nil
    }
  end
end
