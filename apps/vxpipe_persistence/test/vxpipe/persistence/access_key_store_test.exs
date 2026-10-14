defmodule Vxpipe.Persistence.AccessKeyStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Calls.{ApiKeyManagement, InstallationOperator}
  alias Vxpipe.Identity.{Permission, Principal}

  defp options,
    do: [
      access_key_repository: {Vxpipe.Persistence.AccessKeyStore, Repo},
      credential_repository: {Vxpipe.Persistence.CredentialStore, Repo}
    ]

  defp actor(kind) do
    grants = Permission.builtin_grants(kind)

    %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: kind,
      grants: grants,
      assigned_tenants: %{},
      all_tenant_actions: grants
    }
  end

  test "tenant and platform keys persist, authenticate and revoke without exposing stored secrets" do
    {:ok, tenant, _} = Vxpipe.Calls.bootstrap_tenant("Acme", [:calls], options())
    {:ok, other, _} = Vxpipe.Calls.bootstrap_tenant("Other", [:calls], options())
    superadmin = actor(:superadmin)

    assert {:ok, %{key: key, secret: secret}} =
             ApiKeyManagement.create(superadmin, "Backend", "calls", tenant.key, options())

    assert key.tenant.name == "Acme"
    assert key.last_four == String.slice(secret, -4, 4)
    assert {:ok, _} = Vxpipe.Calls.authenticate(tenant.key, secret, :calls, options())

    assert {:error, :insufficient_scope} =
             Vxpipe.Calls.authenticate(tenant.key, secret, :admin, options())

    assert {:error, :invalid_api_key} =
             Vxpipe.Calls.authenticate(other.key, secret, :calls, options())

    assert {:error, :forbidden} =
             ApiKeyManagement.create(actor(:admin), "Platform", "platform", nil, options())

    assert {:ok, %{key: platform, secret: platform_secret}} =
             ApiKeyManagement.create(superadmin, "Platform", "platform", nil, options())

    assert is_nil(platform.tenant)

    assert {:ok, %InstallationOperator{}} =
             Vxpipe.Calls.authenticate_operator(platform_secret, options())

    assert {:ok, _} = Vxpipe.Calls.authenticate(other.key, platform_secret, :calls, options())

    member = %{
      superadmin
      | account_kind: :member,
        grants: MapSet.new(["access_keys.read"]),
        all_tenant_actions: MapSet.new(),
        assigned_tenants: %{tenant.key => :read}
    }

    assert {:ok, %{keys: keys, total: 2}} = ApiKeyManagement.list(member, %{}, options())
    assert Enum.all?(keys, &(&1.tenant.key == tenant.key))
    refute inspect(keys) =~ secret
    assert {:error, :forbidden} = ApiKeyManagement.revoke(member, key.id, options())
    assert :ok = ApiKeyManagement.revoke(superadmin, platform.id, options())

    assert {:error, :invalid_api_key} =
             Vxpipe.Calls.authenticate_operator(platform_secret, options())

    assert :ok = ApiKeyManagement.revoke(superadmin, key.id, options())

    assert {:error, :invalid_api_key} =
             Vxpipe.Calls.authenticate(tenant.key, secret, :calls, options())
  end

  test "tenant search is scoped by the requested access type and paginated on the server" do
    {:ok, tenant, _} = Vxpipe.Calls.bootstrap_tenant("Allowed", [:calls], options())
    Vxpipe.Calls.bootstrap_tenant("Hidden", [:calls], options())

    member = %{
      actor(:admin)
      | account_kind: :member,
        grants:
          MapSet.new(["access_keys.read", "access_keys.write", "calls.read", "calls.write"]),
        all_tenant_actions: MapSet.new(),
        assigned_tenants: %{tenant.key => :read_write}
    }

    assert {:ok, %{tenants: [%{name: "Allowed"}], total: 1}} =
             ApiKeyManagement.tenants(member, "calls", %{"q" => "allow"}, options())

    assert {:ok, %{tenants: [], total: 0}} =
             ApiKeyManagement.tenants(member, "full", %{}, options())

    assert {:error, :forbidden} =
             ApiKeyManagement.create(member, "Escalation", "full", tenant.key, options())

    assert {:error, :invalid_query} = ApiKeyManagement.list(member, %{"page" => "0"}, options())
  end
end
