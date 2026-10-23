defmodule Vxpipe.Calls.OAuthTenantScopeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls.UserAuthorization
  alias Vxpipe.Identity.Principal

  @a "tenant_a_key0001"
  @b "tenant_b_key0002"

  test "admin identity cannot bypass the delegated directory ceiling" do
    actor = principal(:admin, %{}, ["calls.read"])

    assert {:assigned, [@a]} = UserAuthorization.visible_tenant_scope(actor)
    assert :ok = UserAuthorization.authorize_any_tenant(actor, "calls.read")
    assert {:error, :forbidden} = UserAuthorization.authorize_tenant(actor, "calls.read", @b)
    assert {:error, :forbidden} = UserAuthorization.authorize_any_tenant(actor, "calls.write")
  end

  test "mixed all/assigned grants retain separate current and approved contexts" do
    actor = principal(:member, %{@b => :read_write}, ["call_specs.read"])

    actor = %{
      actor
      | delegation: %{
          assigned_tenants: %{@a => :read_write},
          all_tenant_actions: MapSet.new(["calls.read"])
        }
    }

    assert {:assigned, keys} = UserAuthorization.visible_tenant_scope(actor)
    assert keys == Enum.sort([@a, @b])
    assert :ok = UserAuthorization.authorize_tenant(actor, "calls.read", @b)
    assert {:error, :forbidden} = UserAuthorization.authorize_tenant(actor, "calls.read", @a)
    assert :ok = UserAuthorization.authorize_tenant(actor, "call_specs.read", @a)
    assert {:error, :forbidden} = UserAuthorization.authorize_tenant(actor, "call_specs.read", @b)
  end

  test "approved all-tenant access covers future tenants and empty directories" do
    actor = principal(:member, %{}, ["calls.read"])

    actor = %{
      actor
      | delegation: %{assigned_tenants: %{}, all_tenant_actions: MapSet.new(["calls.read"])}
    }

    assert :all = UserAuthorization.visible_tenant_scope(actor)
    assert :ok = UserAuthorization.authorize_any_tenant(actor, "calls.read")
    assert :ok = UserAuthorization.authorize_tenant(actor, "calls.read", @b)
  end

  test "read-only assignments do not advertise write tools" do
    actor = principal(:member, %{@a => :read}, [])
    actor = %{actor | grants: MapSet.new(["calls.read", "calls.write"])}
    assert :ok = UserAuthorization.authorize_any_tenant(actor, "calls.read")
    assert {:error, :forbidden} = UserAuthorization.authorize_any_tenant(actor, "calls.write")
  end

  defp principal(kind, assigned, all) do
    %Principal{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: nil,
      credential_kind: :oauth,
      oauth_grant_public_id: "22222222-2222-4222-8222-222222222222",
      account_kind: kind,
      grants: MapSet.new(["calls.read", "call_specs.read"]),
      assigned_tenants: assigned,
      all_tenant_actions: MapSet.new(all),
      delegation: %{assigned_tenants: %{@a => :read_write}, all_tenant_actions: MapSet.new()}
    }
  end
end
