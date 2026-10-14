defmodule Vxpipe.Calls.ApiKeyAccessTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.ApiKeyAccess
  alias Vxpipe.Identity.Principal
  @tenant "AAAAAAAAAAAAAAAA"
  @other "BBBBBBBBBBBBBBBB"

  defp member(actions, access \\ :read_write) do
    %Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(actions),
      assigned_tenants: %{@tenant => access},
      all_tenant_actions: MapSet.new()
    }
  end

  test "key permissions are separate and bounded by memberships and issuance authority" do
    principal = member(["access_keys.read", "access_keys.write", "calls.read", "calls.write"])
    assert ApiKeyAccess.scope(principal, :read) == {:keys, [@tenant]}
    assert ApiKeyAccess.authorize_create(principal, "calls", @tenant) == :ok
    assert ApiKeyAccess.authorize_create(principal, "calls", @other) == {:error, :forbidden}
    assert ApiKeyAccess.authorize_create(principal, "full", @tenant) == {:error, :forbidden}
    assert ApiKeyAccess.authorize_create(principal, "platform", nil) == {:error, :forbidden}

    assert ApiKeyAccess.scope(member(["tenant_services.read", "tenant_api_keys.write"]), :read) ==
             {:keys, []}

    assert ApiKeyAccess.authorize_create(
             member(["access_keys.read", "access_keys.write", "calls.write"], :read),
             "calls",
             @tenant
           ) == {:error, :forbidden}
  end

  test "only superadmins may issue platform keys even with forged platform-write grants" do
    principal = member(["platform_api_keys.read", "platform_api_keys.write"])
    assert ApiKeyAccess.authorize_create(principal, "platform", nil) == {:error, :forbidden}
    superadmin = %{principal | account_kind: :superadmin}
    assert ApiKeyAccess.authorize_create(superadmin, "platform", nil) == :ok

    assert ApiKeyAccess.authorize_create(superadmin, "platform", @tenant) ==
             {:error, :invalid_key_type}
  end
end
