defmodule Vxpipe.Persistence.CredentialStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.ApiKey

  @tenant_key "AAAAAAAAAAAAAAAA"
  @first_key_id "11111111-1111-4111-8111-111111111111"
  @second_key_id "22222222-2222-4222-8222-222222222222"

  test "stores only a key digest and enforces tenant-scoped authentication" do
    options = options(@tenant_key, @first_key_id, "vxp_first-secret-value")

    assert {:ok, tenant, issued} =
             Administration.bootstrap_tenant("Example tenant", [:admin], options)

    assert {:ok, principal} =
             Administration.authenticate(tenant.key, issued.secret, :admin, options)

    assert principal.tenant_key == tenant.key
    assert %ApiKey{} = stored = Repo.get_by!(ApiKey, public_id: issued.id)
    assert stored.public_id == issued.id
    refute Integer.to_string(stored.id) in [tenant.key, issued.id]
    assert stored.digest == :crypto.hash(:sha256, issued.secret)
    refute Map.has_key?(Map.from_struct(stored), :secret)

    assert {:error, :invalid_api_key} =
             Administration.authenticate("BBBBBBBBBBBBBBBB", issued.secret, :admin, options)

    assert {:error, :invalid_api_key} =
             Administration.authenticate(tenant.key, Base.encode64(stored.digest), :admin, options)
  end

  test "revokes one key without affecting another" do
    first_options = options(@tenant_key, @first_key_id, "vxp_first-secret-value")

    assert {:ok, tenant, first} =
             Administration.bootstrap_tenant("Example tenant", [:calls], first_options)

    second_options = options(@tenant_key, @second_key_id, "vxp_second-secret-value")

    assert {:ok, second} =
             Administration.issue_api_key(tenant.key, "replacement", [:calls], second_options)

    assert {:ok, _record} = Administration.revoke_api_key(tenant.key, first.id, first_options)

    assert {:error, :invalid_api_key} =
             Administration.authenticate(tenant.key, first.secret, :calls, first_options)

    assert {:ok, _principal} =
             Administration.authenticate(tenant.key, second.secret, :calls, second_options)
  end

  test "maps database uniqueness constraints to safe conflict outcomes" do
    now = DateTime.utc_now()

    tenant = %Vxpipe.Calls.Tenant{key: @tenant_key, name: "One", inserted_at: now}

    key = %{
      id: @first_key_id,
      tenant_key: @tenant_key,
      name: "bootstrap",
      scopes: MapSet.new([:admin]),
      digest: :crypto.hash(:sha256, "first"),
      revoked_at: nil,
      inserted_at: now
    }

    assert {:ok, {_tenant, _key}} = CredentialStore.bootstrap_tenant(Repo, tenant, key)

    assert {:error, :tenant_key_conflict} =
             CredentialStore.bootstrap_tenant(Repo, tenant, %{key | id: @second_key_id})
  end

  defp options(tenant_key, key_id, key_secret) do
    [
      credential_repository: {CredentialStore, Repo},
      tenant_key_generator: fn -> tenant_key end,
      uuid_generator: fn -> key_id end,
      api_key_generator: fn -> key_secret end
    ]
  end
end
