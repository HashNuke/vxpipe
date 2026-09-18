defmodule Vxpipe.Persistence.DemoTenantStoreTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Vxpipe.Calls.Tenant
  alias Vxpipe.Persistence.{DemoTenantStore, Repo}
  alias Vxpipe.Persistence.Schema.Tenant, as: StoredTenant

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "stores one installation binding and returns it on retry" do
    first = %Tenant{
      key: "DEMOabcdefgh1234",
      name: "DemoTenant",
      inserted_at: ~U[2026-09-18 05:00:00Z]
    }

    second = %Tenant{
      key: "OTHERabcdefgh123",
      name: "DemoTenant",
      inserted_at: ~U[2026-09-18 05:01:00Z]
    }

    assert {:ok, stored} = DemoTenantStore.ensure(Repo, first)
    assert stored.key == first.key
    assert {:ok, resumed} = DemoTenantStore.ensure(Repo, second)
    assert resumed == stored

    assert Repo.aggregate(from(tenant in StoredTenant, where: tenant.key == ^first.key), :count) ==
             1
  end

  test "does not adopt an unrelated tenant with the display name" do
    unrelated =
      %StoredTenant{}
      |> StoredTenant.changeset(%{key: "OTHERabcdefgh123", name: "DemoTenant"})
      |> Repo.insert!()

    candidate = %Tenant{
      key: "DEMOabcdefgh1234",
      name: "DemoTenant",
      inserted_at: ~U[2026-09-18 05:00:00Z]
    }

    assert {:ok, stored} = DemoTenantStore.ensure(Repo, candidate)
    assert stored.key == candidate.key
    assert stored.key != unrelated.key
    keys = [unrelated.key, candidate.key]

    assert Repo.aggregate(from(tenant in StoredTenant, where: tenant.key in ^keys), :count) == 2
  end
end
