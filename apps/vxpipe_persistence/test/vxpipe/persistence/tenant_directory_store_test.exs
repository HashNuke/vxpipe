defmodule Vxpipe.Persistence.TenantDirectoryStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Persistence.{AdminStore, Repo}
  alias Vxpipe.Persistence.Schema.Tenant

  @first "SEARCHAAAAAAAAAA"
  @second "SEARCHBBBBBBBBBB"
  @foreign "SEARCHCCCCCCCCCC"

  setup do
    for {key, name} <- [{@first, "Acme 100%_\\"}, {@second, "acme"}, {@foreign, "Acme hidden"}] do
      Repo.insert!(Tenant.changeset(%Tenant{}, %{key: key, name: name}))
    end

    :ok
  end

  test "search applies scope before totals and stable name/key pagination" do
    scope = {:keys, [@first, @second]}
    assert {:ok, {[%{key: @second}], 2}} = AdminStore.search_tenants(Repo, scope, "ACME", 1, 0)
    assert {:ok, {[%{key: @first}], 2}} = AdminStore.search_tenants(Repo, scope, "acme", 1, 1)
    assert {:ok, {[], 2}} = AdminStore.search_tenants(Repo, scope, "acme", 1, 2)
    assert {:ok, {[], 0}} = AdminStore.search_tenants(Repo, {:keys, []}, "acme", 25, 0)
    assert {:ok, {[], 0}} = AdminStore.search_tenants(Repo, scope, "hidden", 25, 0)
  end

  test "name and key matching treats SQL wildcards and backslashes literally" do
    for query <- ["%", "_", "\\", "searchaaaa"] do
      assert {:ok, {[%{key: @first}], 1}} =
               AdminStore.search_tenants(Repo, {:keys, [@first, @second, @foreign]}, query, 25, 0)
    end
  end

  test "landing candidates are bounded extant scoped tenants with deterministic order" do
    assert {:ok, [%{key: @second}, %{key: @first}]} =
             AdminStore.tenant_candidates(Repo, {:keys, [@first, @second, "DELETEDAAAAAAAAA"]}, 2)

    assert {:ok, [%{key: @first}]} = AdminStore.tenant_candidates(Repo, {:keys, [@first]}, 1)
    assert {:ok, []} = AdminStore.tenant_candidates(Repo, {:keys, []}, 2)
  end

  test "query failure remains unavailable instead of an empty scope" do
    repo = Vxpipe.Persistence.TestUnavailableAdminRepo
    assert {:error, :repository_unavailable} = AdminStore.search_tenants(repo, :all, "", 25, 0)
    assert {:error, :repository_unavailable} = AdminStore.tenant_candidates(repo, :all, 2)
  end
end
