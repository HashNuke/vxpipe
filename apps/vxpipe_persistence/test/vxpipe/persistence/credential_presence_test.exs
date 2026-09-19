defmodule Vxpipe.Persistence.CredentialPresenceTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{Administration, ProviderCredential, ProviderCredentials, PublicId}

  alias Vxpipe.Persistence.{
    CredentialCipher,
    CredentialKeyring,
    CredentialStore,
    ProviderCredentialStore,
    Repo
  }

  setup do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Presence tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("test", %{"test" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring]

    %{
      tenant: tenant,
      keyring: keyring,
      context: context,
      options: [provider_credential_repository: {ProviderCredentialStore, context}]
    }
  end

  test "a tenant credential is selected by its presence without a separate policy", data do
    {:ok, _platform} = provision(:platform, data.options)

    credential = %ProviderCredential{
      id: PublicId.uuid(),
      tenant_key: data.tenant.key,
      provider: "google",
      name: "google",
      auth_kind: "api_key"
    }

    {:ok, key_id, ciphertext} =
      CredentialCipher.encrypt(data.keyring, credential, %{"api_key" => "synthetic-own"})

    tenant_row = Repo.get_by!(Vxpipe.Persistence.Schema.Tenant, key: data.tenant.key)

    Repo.insert!(
      Vxpipe.Persistence.Schema.ProviderCredential.changeset(
        %Vxpipe.Persistence.Schema.ProviderCredential{},
        %{
          public_id: credential.id,
          tenant_id: tenant_row.id,
          scope: "tenant",
          provider: "google",
          name: "google",
          auth_kind: "api_key",
          encrypted_payload: ciphertext,
          encryption_key_id: key_id,
          status: "active",
          version: 1,
          payload_schema_version: 1,
          secret_hints: %{}
        }
      )
    )

    assert {:ok, resolved} =
             ProviderCredentials.resolve(data.tenant.key, "google", "google", data.options)

    assert resolved.credential.id == credential.id
    assert resolved.payload == %{"api_key" => "synthetic-own"}

    assert {:ok, %{bindings: [binding]}} =
             ProviderCredentialStore.list_bindings(data.context, data.tenant.key)

    assert binding.source == :tenant
    refute Map.has_key?(binding, :policy)
    refute Map.has_key?(binding, :tenant_credential_id)
  end

  test "removing tenant credentials restores inheritance and scoped deletion cannot remove another owner",
       data do
    {:ok, platform} = provision(:platform, data.options)
    {:ok, own} = provision(data.tenant.key, data.options)

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.delete(data.tenant.key, platform.id, data.options)

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.delete(:platform, own.id, data.options)

    assert :ok = ProviderCredentials.delete(data.tenant.key, own.id, data.options)
    assert Repo.get_by(Vxpipe.Persistence.Schema.ProviderCredential, public_id: own.id) == nil

    assert {:ok, inherited} =
             ProviderCredentials.resolve(data.tenant.key, "google", "google", data.options)

    assert inherited.credential.id == platform.id
    assert :ok = ProviderCredentials.delete(:platform, platform.id, data.options)

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.resolve(data.tenant.key, "google", "google", data.options)
  end

  test "malformed deletion identities return a bounded validation error", data do
    assert {:error, :invalid_provider_credential_id} =
             ProviderCredentials.delete(data.tenant.key, "not-a-uuid", data.options)
  end

  defp provision(owner, options),
    do:
      ProviderCredentials.provision(
        owner,
        "google",
        "google",
        "api_key",
        %{"api_key" => "synthetic-key"},
        options
      )
end
