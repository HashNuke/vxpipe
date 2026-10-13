defmodule Vxpipe.Calls.TenantCreationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.{TenantCreation, TestMemoryRepository}
  alias Vxpipe.Identity.Principal

  setup do
    repository = start_supervised!(TestMemoryRepository)
    [repository: repository, options: [credential_repository: {TestMemoryRepository, repository}]]
  end

  test "authorized creation stores a tenant without issuing an API key", context do
    assert {:ok, tenant} =
             TenantCreation.create(principal(["tenants.write"]), "  Support  ", context.options)

    assert tenant.name == "Support"
    assert byte_size(tenant.key) == 16
    assert {:ok, ^tenant} = TestMemoryRepository.fetch_tenant(context.repository, tenant.key)
    assert TestMemoryRepository.stored_api_keys(context.repository) == []
  end

  test "denied and invalid requests do not require a repository" do
    assert {:error, :forbidden} = TenantCreation.create(principal([]), "Support", [])

    for name <- [nil, "", "  ", String.duplicate("x", 257)] do
      assert {:error, :invalid_tenant_name} =
               TenantCreation.create(principal(["tenants.write"]), name, [])
    end
  end

  defp principal(grants),
    do: %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(grants)
    }
end
