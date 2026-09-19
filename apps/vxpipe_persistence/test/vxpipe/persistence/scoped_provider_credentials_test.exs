defmodule Vxpipe.Persistence.ScopedProviderCredentialsTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls.{Administration, ProviderCredentials, ProviderCredentialSource}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, ProviderCredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.ProviderCredential

  setup do
    tenants =
      for name <- ["First inheritor", "Second inheritor", "Override tenant"] do
        {:ok, tenant, _issued} =
          Administration.bootstrap_tenant(name, [:admin],
            credential_repository: {CredentialStore, Repo}
          )

        tenant
      end

    {:ok, keyring} =
      CredentialKeyring.new("scope-v1", %{"scope-v1" => :crypto.strong_rand_bytes(32)})

    context = [repo: Repo, keyring: keyring]
    options = [provider_credential_repository: {ProviderCredentialStore, context}]
    %{tenants: tenants, context: context, options: options}
  end

  test "two tenants inherit a named platform credential while a third uses its own", data do
    [first, second, third] = data.tenants

    assert {:ok, platform} =
             provision(:platform, "shared-model", "platform-example", data.options)

    assert platform.owner == :platform
    assert platform.tenant_key == nil

    assert {:ok, override} = provision(third.key, "shared-model", "tenant-example", data.options)

    for tenant <- [first, second] do
      assert {:ok, resolved} =
               ProviderCredentials.resolve(tenant.key, "google", "shared-model", data.options)

      assert resolved.credential.id == platform.id
      assert resolved.credential.owner == :platform
      assert resolved.payload == %{"api_key" => "platform-example"}

      assert {:ok, runtime} =
               ProviderCredentialSource.resolve(
                 data.options,
                 tenant.key,
                 "google",
                 "shared-model"
               )

      assert runtime.tenant_id == tenant.key
      assert runtime.id == platform.id
    end

    assert {:ok, own} =
             ProviderCredentials.resolve(third.key, "google", "shared-model", data.options)

    assert own.credential.id == override.id
    assert own.credential.owner == {:tenant, third.key}
    assert own.payload == %{"api_key" => "tenant-example"}

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.resolve(first.key, "google", "default", data.options)

    requirements = [%{provider: "google", name: "shared-model", path: ["model"]}]

    assert {:ok, :saved} =
             ProviderCredentialStore.with_active(data.context, first.key, requirements, fn ->
               {:ok, :saved}
             end)
  end

  test "unusable tenant credentials fail closed until removed",
       data do
    [tenant | _] = data.tenants

    assert {:ok, platform} =
             provision(:platform, "shared-model", "platform-example", data.options)

    assert {:ok, override} = provision(tenant.key, "shared-model", "tenant-example", data.options)

    stored = Repo.get_by!(ProviderCredential, public_id: override.id)
    Repo.update!(Ecto.Changeset.change(stored, status: "revoked"))

    assert {:error, :provider_credential_revoked} =
             ProviderCredentials.resolve(tenant.key, "google", "shared-model", data.options)

    requirements = [%{provider: "google", name: "shared-model", path: ["model"]}]

    assert {:error, {:provider_credential_unavailable, ["model"]}} =
             ProviderCredentialStore.with_active(data.context, tenant.key, requirements, fn ->
               flunk("unusable credentials reached the write")
             end)

    assert :ok = ProviderCredentials.delete(tenant.key, override.id, data.options)

    assert {:ok, inherited} =
             ProviderCredentials.resolve(tenant.key, "google", "shared-model", data.options)

    assert inherited.credential.id == platform.id
  end

  test "platform ciphertext cannot be transplanted into a tenant and both scopes re-encrypt",
       data do
    [tenant | _] = data.tenants

    assert {:ok, platform} =
             provision(:platform, "shared-model", "platform-example", data.options)

    assert {:ok, override} = provision(tenant.key, "shared-model", "tenant-example", data.options)
    shared_row = Repo.get_by!(ProviderCredential, public_id: platform.id)
    tenant_row = Repo.get_by!(ProviderCredential, public_id: override.id)
    assert <<2, _rest::binary>> = shared_row.encrypted_payload
    assert <<1, _rest::binary>> = tenant_row.encrypted_payload

    Repo.update!(
      Ecto.Changeset.change(tenant_row, encrypted_payload: shared_row.encrypted_payload)
    )

    assert {:error, :provider_credential_unreadable} =
             ProviderCredentials.resolve(tenant.key, "google", "shared-model", data.options)

    tenant_row
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:encrypted_payload, tenant_row.encrypted_payload)
    |> Repo.update!()

    old = Keyword.fetch!(data.context, :keyring)
    assert {:ok, old_key} = CredentialKeyring.fetch(old, "scope-v1")
    next_key = :crypto.strong_rand_bytes(32)

    assert {:ok, next} =
             CredentialKeyring.new("scope-v2", %{"scope-v1" => old_key, "scope-v2" => next_key})

    assert {:ok, %{processed: 2, remaining_by_key: %{}}} =
             ProviderCredentialStore.reencrypt(Keyword.put(data.context, :keyring, next))

    assert {:ok, retired} = CredentialKeyring.new("scope-v2", %{"scope-v2" => next_key})
    context = Keyword.put(data.context, :keyring, retired)

    for {owner, expected} <- [{:platform, "platform-example"}, {tenant.key, "tenant-example"}] do
      assert {:ok, resolved} =
               ProviderCredentialStore.resolve(context, owner, "google", "shared-model")

      assert resolved.payload == %{"api_key" => expected}
    end
  end

  test "operator directory reports exact effective bindings without secret material", data do
    [tenant, other | _] = data.tenants

    {:ok, platform} =
      provision(:platform, "shared-model", "shared-directory-secret", data.options)

    {:ok, own} = provision(tenant.key, "shared-model", "own-directory-secret", data.options)
    {:ok, _foreign} = provision(other.key, "foreign", "foreign-directory-secret", data.options)

    assert {:ok, directory} = ProviderCredentialStore.list_bindings(data.context, tenant.key)
    assert directory.tenant.key == tenant.key
    assert [binding] = directory.bindings
    assert binding.name == "shared-model"
    assert binding.source == :tenant
    assert binding.credential_id == own.id
    assert binding.platform_available
    assert binding.status == :connected

    assert :ok = ProviderCredentials.delete(tenant.key, own.id, data.options)

    assert {:ok, inherited} = ProviderCredentialStore.list_bindings(data.context, tenant.key)
    assert [binding] = inherited.bindings
    assert binding.credential_id == platform.id
    assert binding.source == :platform

    assert {:ok, platform_directory} =
             ProviderCredentialStore.list_bindings(data.context, :platform)

    assert platform_directory.tenant == nil
    assert [%{credential_id: id, source: :platform}] = platform_directory.bindings
    assert id == platform.id

    for directory <- [directory, inherited, platform_directory] do
      inspected = inspect(directory)
      refute inspected =~ "directory-secret"
      refute inspected =~ "encrypted_payload"
      refute inspected =~ "foreign"
    end

    assert {:error, :tenant_not_found} =
             ProviderCredentialStore.list_bindings(data.context, "ZZZZZZZZZZZZZZZZ")
  end

  test "Telnyx directory exposes configured fields only from the selected whole credential",
       data do
    [tenant | _] = data.tenants
    public_key = Base.encode64(<<1::256>>)

    assert {:ok, _platform} =
             ProviderCredentials.provision(
               :platform,
               "telnyx",
               "telnyx",
               "api_key",
               %{"api_key" => "directory-api-private", "public_key" => public_key},
               data.options
             )

    assert {:ok, inherited} = ProviderCredentialStore.list_bindings(data.context, tenant.key)
    assert [%{saved_fields: ["api_key", "public_key"], source: :platform}] = inherited.bindings
    refute inspect(inherited) =~ public_key
    refute inspect(inherited) =~ "directory-api-private"

    assert {:ok, override} =
             ProviderCredentials.provision(
               tenant.key,
               "telnyx",
               "telnyx",
               "api_key",
               %{"api_key" => "directory-tenant-private"},
               data.options
             )

    assert {:ok, own} = ProviderCredentialStore.list_bindings(data.context, tenant.key)
    assert [%{saved_fields: ["api_key"], source: :tenant}] = own.bindings

    stored = Repo.get_by!(ProviderCredential, public_id: override.id)
    <<first, rest::binary>> = stored.encrypted_payload

    Repo.update!(
      Ecto.Changeset.change(stored, encrypted_payload: <<Bitwise.bxor(first, 1), rest::binary>>)
    )

    assert {:ok, unreadable} = ProviderCredentialStore.list_bindings(data.context, tenant.key)
    assert [%{saved_fields: [], source: :tenant, status: :unavailable}] = unreadable.bindings
  end

  defp provision(owner, name, secret, options) do
    ProviderCredentials.provision(
      owner,
      "google",
      name,
      "api_key",
      %{"api_key" => secret},
      options
    )
  end
end
