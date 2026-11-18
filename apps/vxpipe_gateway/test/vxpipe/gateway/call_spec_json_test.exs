defmodule Vxpipe.Gateway.CallSpecJSONTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Gateway.CallSpecJSON

  test "publication status preserves request identity and serializes only reference history" do
    stored =
      struct!(Vxpipe.Calls.CallSpecRevision, %{
        tenant_key: "tenant",
        call_spec_id: "123",
        revision: 9,
        schema_version: "20261004.01",
        source: %{},
        source_digest: "digest",
        compiled_metadata: %{},
        validation_errors: [],
        routes: [],
        telephony_routes: [],
        published_at: nil,
        inserted_at: ~U[2026-11-17 12:00:00Z],
        publication: %{
          version: 2,
          revision: 7,
          unpublished_changes: false,
          draft_saved_at: ~U[2026-11-17 12:00:00Z],
          history: [%{version: 2, published_at: ~U[2026-11-17 11:00:00Z]}]
        }
      })

    result = CallSpecJSON.write_revision(stored)
    assert result.revision == 9
    refute result.published

    assert result.publication == %{
             version: 2,
             revision: 7,
             unpublished_changes: false,
             draft_saved_at: "2026-11-17T12:00:00Z",
             history: [%{version: 2, published_at: "2026-11-17T11:00:00Z"}]
           }
  end
end
