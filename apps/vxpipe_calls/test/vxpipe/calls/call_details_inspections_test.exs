defmodule Vxpipe.Calls.CallDetailsInspectionsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    CallDetailsDocument,
    CallDetailsRevision,
    Principal,
    TestCallDetailsInspectionRepository
  }

  @tenant_key "TENANT001"
  @call_id "call-details-inspection"

  test "lists bounded revisions with an opaque continuation and fetches exact published JSON" do
    revisions = [
      revision("publication-1", 1),
      revision("publication-2", 2),
      revision("publication-3", 3)
    ]

    document = document("publication-3")

    repository =
      start_supervised!(
        {TestCallDetailsInspectionRepository,
         revisions: %{{@tenant_key, @call_id} => revisions},
         documents: %{{@tenant_key, @call_id, document.id} => document}}
      )

    options = [
      call_details_inspection_repository:
        TestCallDetailsInspectionRepository.repository(repository),
      limit: 2
    ]

    assert {:ok, first} = Calls.list_call_details(principal(), @call_id, options)
    assert Enum.map(first.revisions, & &1.id) == ["publication-3", "publication-2"]
    assert is_binary(first.next_cursor)
    refute first.next_cursor =~ "publication-2"

    assert {:ok, second} =
             Calls.list_call_details(
               principal(),
               @call_id,
               Keyword.put(options, :cursor, first.next_cursor)
             )

    assert Enum.map(second.revisions, & &1.id) == ["publication-1"]
    assert second.next_cursor == nil

    assert {:ok, ^document} =
             Calls.fetch_call_details(principal(), @call_id, document.id, options)

    assert TestCallDetailsInspectionRepository.operations(repository) == [
             {:list, @tenant_key, @call_id, 3, nil},
             {:list, @tenant_key, @call_id, 3, {~U[2026-09-12 20:00:02.000Z], "publication-2"}},
             {:fetch, @tenant_key, @call_id, "publication-3"}
           ]
  end

  test "rejects unauthorized and malformed requests before repository access" do
    repository = start_supervised!(TestCallDetailsInspectionRepository)

    options = [
      call_details_inspection_repository:
        TestCallDetailsInspectionRepository.repository(repository)
    ]

    unauthorized = %{principal() | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Calls.list_call_details(unauthorized, @call_id, options)

    assert {:error, :invalid_cursor} =
             Calls.list_call_details(principal(), @call_id, Keyword.put(options, :cursor, "bad"))

    assert {:error, :invalid_call_details_request} =
             Calls.fetch_call_details(principal(), @call_id, "", options)

    assert TestCallDetailsInspectionRepository.operations(repository) == []
  end

  defp revision(id, second) do
    %CallDetailsRevision{
      id: id,
      recorded_at: DateTime.add(~U[2026-09-12 20:00:00.000Z], second, :second),
      filename: "details-2026091220000#{second}000.json",
      completeness: if(second == 3, do: :complete, else: :incomplete),
      status: if(second == 1, do: :pending, else: :published),
      checksum: "sha256:#{String.duplicate(Integer.to_string(second), 64)}",
      size_bytes: 100 + second,
      published_at:
        if(second == 1, do: nil, else: DateTime.add(~U[2026-09-12 20:01:00Z], second)),
      latest?: second == 3
    }
  end

  defp document(id) do
    %CallDetailsDocument{
      id: id,
      recorded_at: ~U[2026-09-12 20:00:03.000Z],
      filename: "details-20260912200003000.json",
      completeness: :complete,
      checksum: "sha256:#{String.duplicate("3", 64)}",
      contents: ~s({"schema_version":"20260912.01"}),
      published_at: ~U[2026-09-12 20:01:03.000Z]
    }
  end

  defp principal do
    %Principal{
      tenant_key: @tenant_key,
      api_key_id: "key-calls",
      scopes: MapSet.new([:calls])
    }
  end
end
