defmodule Vxpipe.Persistence.OperatorApiKeyStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.InstallationOperator

  defp options do
    [operator_api_key_repository: {Vxpipe.Persistence.OperatorApiKeyStore, Repo}]
  end

  test "bootstrap emits one operator key, stores a digest and never promotes tenant keys" do
    assert {:ok, issued} = Calls.bootstrap_operator_api_key(options())
    assert String.starts_with?(issued.secret, "vxop_")
    refute inspect(issued) =~ issued.secret

    assert {:ok, %InstallationOperator{api_key_id: key_id}} =
             Calls.authenticate_operator(issued.secret, options())

    assert key_id == issued.id

    stored = Repo.get_by!(Vxpipe.Persistence.Schema.OperatorApiKey, public_id: issued.id)
    assert stored.digest == :crypto.hash(:sha256, issued.secret)
    refute Map.has_key?(Map.from_struct(stored), :secret)

    assert {:error, :operator_key_already_initialized} =
             Calls.bootstrap_operator_api_key(options())

    assert {:error, :invalid_api_key} =
             Calls.authenticate_operator(Base.encode64(stored.digest), options())

    tenant_options = [credential_repository: {Vxpipe.Persistence.CredentialStore, Repo}]

    {:ok, tenant, tenant_key} =
      Calls.bootstrap_tenant("Key isolation", [:admin, :calls], tenant_options)

    assert {:error, :invalid_api_key} = Calls.authenticate_operator(tenant_key.secret, options())

    assert {:error, :invalid_api_key} =
             Calls.authenticate(tenant.key, issued.secret, :admin, tenant_options)
  end

  test "explicit replacement revokes the old key atomically and revocation survives bootstrap retries" do
    {:ok, first} = Calls.bootstrap_operator_api_key(options())
    conflicting = Keyword.put(options(), :uuid_generator, fn -> first.id end)
    assert {:error, :operator_key_conflict} = Calls.replace_operator_api_key(conflicting)
    assert {:ok, _} = Calls.authenticate_operator(first.secret, options())

    assert {:ok, replacement} = Calls.replace_operator_api_key(options())
    assert {:error, :invalid_api_key} = Calls.authenticate_operator(first.secret, options())
    assert {:ok, _} = Calls.authenticate_operator(replacement.secret, options())

    assert {:ok, %{id: id, revoked_at: %DateTime{}}} =
             Calls.revoke_operator_api_key(replacement.id, options())

    assert id == replacement.id
    assert {:error, :invalid_api_key} = Calls.authenticate_operator(replacement.secret, options())

    assert {:error, :operator_key_already_initialized} =
             Calls.bootstrap_operator_api_key(options())
  end
end
