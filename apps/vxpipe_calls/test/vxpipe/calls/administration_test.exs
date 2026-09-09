defmodule Vxpipe.Calls.AdministrationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.{Administration, IssuedApiKey, Principal}
  alias Vxpipe.Calls.TestMemoryRepository

  setup do
    repository = start_supervised!(TestMemoryRepository)
    [options: [credential_repository: TestMemoryRepository.credential_repository(repository)]]
  end

  test "bootstraps a tenant and returns its hash-only stored API key once", %{options: options} do
    assert {:ok, tenant, %IssuedApiKey{} = issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin, :calls], options)

    assert byte_size(tenant.key) == 16
    refute String.contains?(tenant.key, "=")
    assert issued.tenant_key == tenant.key
    assert issued.scopes == MapSet.new([:admin, :calls])
    assert is_binary(issued.secret)
    assert byte_size(issued.secret) >= 43
    assert inspect(issued) =~ "secret: \"[REDACTED]\""
    refute inspect(issued) =~ issued.secret

    {TestMemoryRepository, repository} = Keyword.fetch!(options, :credential_repository)
    assert [stored] = TestMemoryRepository.stored_api_keys(repository)
    assert stored.digest == :crypto.hash(:sha256, issued.secret)
    refute Map.has_key?(stored, :secret)
  end

  test "authenticates explicit tenant scopes without an implicit hierarchy", %{options: options} do
    assert {:ok, tenant, admin_key} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    assert {:ok, %Principal{tenant_key: tenant_key, scopes: scopes}} =
             Administration.authenticate(tenant.key, admin_key.secret, :admin, options)

    assert tenant_key == tenant.key
    assert scopes == MapSet.new([:admin])

    assert {:error, :insufficient_scope} =
             Administration.authenticate(tenant.key, admin_key.secret, :calls, options)

    assert {:error, :invalid_api_key} =
             Administration.authenticate(tenant.key, "wrong key", :admin, options)

    assert {:error, :invalid_api_key} =
             Administration.authenticate("AAAAAAAAAAAAAAAA", admin_key.secret, :admin, options)
  end

  test "rotates and independently revokes tenant API keys", %{options: options} do
    assert {:ok, tenant, first} =
             Administration.bootstrap_tenant("Example tenant", [:calls], options)

    assert {:ok, second} =
             Administration.issue_api_key(tenant.key, "replacement", [:calls], options)

    assert first.id != second.id
    assert first.secret != second.secret
    assert {:ok, _principal} =
             Administration.authenticate(tenant.key, first.secret, :calls, options)

    assert {:ok, _revoked} = Administration.revoke_api_key(tenant.key, first.id, options)

    assert {:error, :invalid_api_key} =
             Administration.authenticate(tenant.key, first.secret, :calls, options)

    assert {:ok, _principal} =
             Administration.authenticate(tenant.key, second.secret, :calls, options)
  end
end
