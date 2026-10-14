defmodule Vxpipe.Calls.CallSpecSearchTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.CallSpecSearch
  alias Vxpipe.Identity.Principal
  @key "AAAAAAAAAAAAAAAA"

  test "calls-only readers can search their tenant, with authorization before storage" do
    {:ok, principal} =
      Principal.new(%{
        user_public_id: "user",
        session_public_id: "session",
        account_kind: :member,
        grants: ["calls.read"],
        assigned_tenants: %{@key => :read}
      })

    opts = [admin_repository: {__MODULE__, self()}]
    assert {:ok, {[], false}} = CallSpecSearch.search(principal, @key, " Intake ", 2, opts)
    assert_received {:search, @key, "Intake", 25, 25}
    assert {:error, _} = CallSpecSearch.search(principal, "BBBBBBBBBBBBBBBB", "", 1, opts)
    refute_received {:search, _, _, _, _}
    assert {:error, :invalid_search} = CallSpecSearch.search(principal, @key, [], 1, opts)
    assert {:error, :invalid_search} = CallSpecSearch.search(principal, @key, "", 0, opts)

    assert {:error, :invalid_search} =
             CallSpecSearch.search(principal, @key, String.duplicate("x", 257), 1, opts)

    refute_received {:search, _, _, _, _}
  end

  def search_call_specs(owner, key, query, limit, offset) do
    send(owner, {:search, key, query, limit, offset})
    {:ok, {[], false}}
  end
end
