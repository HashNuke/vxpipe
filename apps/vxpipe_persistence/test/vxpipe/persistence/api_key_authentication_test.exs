defmodule Vxpipe.Persistence.ApiKeyAuthenticationTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{ApiKeyManagement, InstallationOperator, Principal}
  alias Vxpipe.Identity.Permission
  alias Vxpipe.Persistence.{AccessKeyStore, CredentialStore, OperatorApiKeyStore}

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      access_key_repository: {AccessKeyStore, Repo},
      operator_api_key_repository: {OperatorApiKeyStore, Repo}
    ]

    [options: options]
  end

  test "discovers tenant keys and rechecks revocation in persistent storage", %{options: options} do
    {:ok, tenant, _} = Calls.bootstrap_tenant("Tenant", [:calls], options)

    for kind <- ["calls", "full"] do
      {:ok, %{key: key, secret: secret}} =
        ApiKeyManagement.create(superadmin(), kind, kind, tenant.key, options)

      assert {:ok, %Principal{api_key_id: id, tenant_key: tenant_key, scopes: scopes}} =
               Calls.authenticate_api_key(secret, options)

      assert id == key.id
      assert tenant_key == tenant.key
      assert scopes == MapSet.new(if(kind == "calls", do: [:calls], else: [:admin, :calls]))
      assert :ok = ApiKeyManagement.revoke(superadmin(), key.id, options)
      assert {:error, :invalid_api_key} = Calls.authenticate_api_key(secret, options)
    end
  end

  test "duplicate tenant digests remain usable only with explicit tenant scope", %{
    options: options
  } do
    options = Keyword.put(options, :api_key_generator, fn -> "vxp_duplicate-synthetic-secret" end)
    {:ok, first, issued} = Calls.bootstrap_tenant("First", [:calls], options)
    {:ok, second, _} = Calls.bootstrap_tenant("Second", [:admin], options)

    assert {:error, :ambiguous_api_key} =
             CredentialStore.fetch_api_key_by_digest(Repo, :crypto.hash(:sha256, issued.secret))

    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(issued.secret, options)
    assert {:ok, _} = Calls.authenticate(first.key, issued.secret, :calls, options)
    assert {:ok, _} = Calls.authenticate(second.key, issued.secret, :admin, options)
    assert {:ok, _} = Calls.revoke_api_key(first.key, issued.id, options)
    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(issued.secret, options)
  end

  test "platform authentication preserves Settings provenance and excludes legacy operators", %{
    options: options
  } do
    {:ok, %{key: key, secret: secret}} =
      ApiKeyManagement.create(superadmin(), "Platform", "platform", nil, options)

    assert {:ok, %InstallationOperator{} = actor} = Calls.authenticate_api_key(secret, options)
    assert actor.api_key_id == key.id
    assert actor.credential_kind == :platform_api_key

    assert {:ok, legacy} = Calls.bootstrap_operator_api_key(options)

    assert {:ok, %InstallationOperator{} = legacy_actor} =
             Calls.authenticate_operator(legacy.secret, options)

    assert legacy_actor.credential_kind == :legacy_operator_api_key
    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(legacy.secret, options)

    assert :ok = ApiKeyManagement.revoke(superadmin(), key.id, options)
    assert {:error, :invalid_api_key} = Calls.authenticate_api_key(secret, options)
  end

  defp superadmin do
    grants = Permission.builtin_grants(:superadmin)

    %Vxpipe.Identity.Principal{
      user_public_id: "synthetic-user",
      session_public_id: "synthetic-session",
      account_kind: :superadmin,
      grants: grants,
      assigned_tenants: %{},
      all_tenant_actions: grants
    }
  end
end
