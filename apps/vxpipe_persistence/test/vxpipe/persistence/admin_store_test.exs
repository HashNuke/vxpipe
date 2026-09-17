defmodule Vxpipe.Persistence.AdminStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{Administration, InstallationOperator}
  alias Vxpipe.Persistence.{AdminStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.Tenant
  alias Vxpipe.Persistence.TestUnavailableAdminRepo

  test "lists tenants in a deterministic bounded page with a total" do
    existing_total = Repo.aggregate(Tenant, :count)

    for {name, key} <- [
          {"Oldest", "AAAAAAAAAAAAAAAA"},
          {"Middle", "BBBBBBBBBBBBBBBB"},
          {"Newest", "CCCCCCCCCCCCCCCC"}
        ] do
      assert {:ok, _tenant, _issued} =
               Administration.bootstrap_tenant(name, [:admin],
                 credential_repository: {CredentialStore, Repo},
                 tenant_key_generator: fn -> key end
               )
    end

    assert {:ok, {ordered, total}} = AdminStore.list_tenants(Repo, existing_total + 3, 0)

    assert total == existing_total + 3
    assert Enum.map(Enum.take(ordered, 3), & &1.name) == ["Newest", "Middle", "Oldest"]

    assert {:ok, page} =
             Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(),
               page: 2,
               limit: 2,
               admin_repository: {AdminStore, Repo}
             )

    assert page.page == 2
    assert page.page_size == 2
    assert page.total == existing_total + 3
    assert page.total_pages == div(existing_total + 4, 2)
    assert page.tenants == Enum.slice(ordered, 2, 2)

    assert {:ok, {[], ^total}} = AdminStore.list_tenants(Repo, 2, total + 1)
  end

  test "translates an unavailable repository into the port error contract" do
    assert {:error, :repository_unavailable} =
             AdminStore.list_tenants(TestUnavailableAdminRepo, 25, 0)
  end
end
