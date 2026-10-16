defmodule Vxpipe.Identity.OAuth.DelegationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.{Authorization, Principal}
  alias Vxpipe.Identity.AccountAuthority
  alias Vxpipe.Identity.OAuth.Delegation

  @user_id "11111111-1111-4111-8111-111111111111"
  @session_id "22222222-2222-4222-8222-222222222222"
  @role_id "33333333-3333-4333-8333-333333333333"
  @grant_id "44444444-4444-4444-8444-444444444444"
  @tenant_a "tenant_a_key0001"
  @tenant_b "tenant_b_key0002"

  test "trusted session construction carries the consent version without changing browser authority" do
    assert {:ok, principal} = Principal.for_session(user(), role(), %{public_id: @session_id})
    assert principal.credential_kind == :browser_session
    assert principal.session_public_id == @session_id
    assert principal.oauth_grant_public_id == nil

    assert %{
             authorization_version: 2,
             role_public_id: @role_id,
             role_revision: 3,
             authority: %{"assigned_tenants" => %{@tenant_a => "read_write"}}
           } = Delegation.snapshot(principal)
  end

  test "OAuth principal carries a grant and no fabricated browser session" do
    assert {:ok, principal} = Delegation.principal(user(), role(), grant())
    assert principal.credential_kind == :oauth
    assert principal.session_public_id == nil
    assert principal.oauth_grant_public_id == @grant_id
    assert principal.user_public_id == @user_id

    assert {:error, :invalid_principal} =
             Principal.new(%{
               user_public_id: @user_id,
               session_public_id: @session_id,
               oauth_grant_public_id: @grant_id,
               credential_kind: :oauth,
               account_kind: :member,
               grants: ["calls.read"]
             })
  end

  test "different user, changed authorization version or role revision invalidates delegation" do
    for changed <- [
          Map.put(grant(), :user_public_id, @session_id),
          Map.put(grant(), :authorization_version, 1),
          Map.put(grant(), :role_public_id, @session_id),
          Map.put(grant(), :role_revision, 2)
        ] do
      assert {:error, :invalid_grant} = Delegation.principal(user(), role(), changed)
    end
  end

  test "account attribution preserves OAuth provenance and cannot be supplied through user fields" do
    {:ok, principal} = Delegation.principal(user(), role(), grant())
    assert :ok = AccountAuthority.require_identity(principal)

    assert AccountAuthority.attribution(principal) == %{
             actor_user_public_id: @user_id,
             actor_oauth_grant_public_id: @grant_id
           }

    stamped =
      AccountAuthority.stamp(
        %{
          "actor_oauth_grant_public_id" => @session_id,
          actor_session_public_id: @session_id
        },
        AccountAuthority.attribution(principal)
      )

    refute Map.has_key?(stamped, "actor_oauth_grant_public_id")
    refute Map.has_key?(stamped, :actor_session_public_id)
    assert stamped.actor_oauth_grant_public_id == @grant_id
  end

  test "mixed all-tenant and assigned approval is checked per action, without a union leaking access" do
    current_user = %{user() | memberships: %{@tenant_b => :read_write}}

    current_role = %{
      role()
      | grants: [
          %{permission: "calls.read", scope: :assigned_tenants},
          %{permission: "call_specs.read", scope: :all_tenants}
        ]
    }

    authority = %{
      "grants" => ["calls.read", "call_specs.read"],
      "assigned_tenants" => %{@tenant_a => "read_write"},
      "all_tenant_actions" => ["calls.read"],
      "account_kind" => "member"
    }

    assert {:ok, principal} =
             Delegation.principal(current_user, current_role, %{grant() | authority: authority})

    assert :ok = authorize(principal, "calls.read", @tenant_b)
    assert {:error, :forbidden} = authorize(principal, "calls.read", @tenant_a)
    assert :ok = authorize(principal, "call_specs.read", @tenant_a)
    assert {:error, :forbidden} = authorize(principal, "call_specs.read", @tenant_b)
  end

  test "approved read caps and permissions restrict a currently more privileged user" do
    authority = %{grant().authority | "assigned_tenants" => %{@tenant_a => "read"}}

    assert {:ok, principal} =
             Delegation.principal(user(), role(), %{grant() | authority: authority})

    assert :ok = authorize(principal, "calls.read", @tenant_a)
    assert {:error, :forbidden} = authorize(principal, "calls.write", @tenant_a)
    refute MapSet.member?(principal.grants, "users.read")
  end

  defp authorize(principal, action, tenant),
    do: Authorization.authorize(principal.grants, action, {:tenant, tenant}, principal)

  defp user do
    %{
      public_id: @user_id,
      disabled_at: nil,
      authorization_version: 2,
      role_public_id: @role_id,
      memberships: %{@tenant_a => :read_write}
    }
  end

  defp role do
    %{
      public_id: @role_id,
      revision: 3,
      kind: :member,
      grants: [
        %{permission: "calls.read", scope: :assigned_tenants},
        %{permission: "calls.write", scope: :assigned_tenants},
        %{permission: "call_specs.read", scope: :assigned_tenants}
      ]
    }
  end

  defp grant do
    %{
      public_id: @grant_id,
      user_public_id: @user_id,
      authorization_version: 2,
      role_public_id: @role_id,
      role_revision: 3,
      authority: %{
        "grants" => ["calls.read", "calls.write", "call_specs.read"],
        "assigned_tenants" => %{@tenant_a => "read_write"},
        "all_tenant_actions" => [],
        "account_kind" => "member"
      }
    }
  end
end
