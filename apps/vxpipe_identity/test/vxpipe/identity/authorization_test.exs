defmodule Vxpipe.Identity.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Authorization

  test "exact category matrix: members write never implies privileged writes" do
    member_grants = MapSet.new(["users.read", "users.members.write"])

    assert :ok =
             Authorization.require_account_write(member_grants, :member, :member)

    assert {:error, :forbidden} =
             Authorization.require_account_write(member_grants, :member, :admin)

    assert {:error, :forbidden} =
             Authorization.require_account_write(member_grants, :admin, :admin)
  end

  test "admin can manage members but only view privileged accounts" do
    admin_grants = MapSet.new(["users.read", "users.members.write"])
    assert :ok = Authorization.require_account_write(admin_grants, :member, :member)

    assert {:error, :forbidden} =
             Authorization.require_account_write(admin_grants, :member, :admin)

    assert {:error, :forbidden} =
             Authorization.require_account_write(admin_grants, :admin, :superadmin)
  end

  test "superadmin holds all three writes; promotion needs both kinds" do
    grants =
      MapSet.new([
        "users.read",
        "users.members.write",
        "users.admins.write",
        "users.superadmins.write"
      ])

    assert :ok = Authorization.require_account_write(grants, :member, :admin)
    assert :ok = Authorization.require_account_write(grants, :admin, :superadmin)
    assert :ok = Authorization.require_account_write(grants, :superadmin, :superadmin)
  end

  test "promotion without both kinds is denied even for superadmin subsets" do
    partial = MapSet.new(["users.read", "users.members.write", "users.admins.write"])
    assert {:error, :forbidden} = Authorization.require_account_write(partial, :admin, :superadmin)
    assert {:error, :forbidden} = Authorization.require_account_write(partial, :member, :superadmin)
  end

  test "account creation authorizes target kind only" do
    admin_grants = MapSet.new(["users.read", "users.members.write"])

    assert :ok = Authorization.require_account_create(admin_grants, :member)
    assert {:error, :forbidden} = Authorization.require_account_create(admin_grants, :admin)
    assert {:error, :forbidden} = Authorization.require_account_create(admin_grants, :superadmin)
  end

  test "unknown actions deny even for built-ins" do
    grants =
      MapSet.new([
        "users.read",
        "users.members.write",
        "users.admins.write",
        "users.superadmins.write"
      ])

    assert {:error, :unknown_action} = Authorization.authorize(grants, "nope.deny", :installation, nil)
  end

  test "ordinary role names never substitute for a grant" do
    assert {:error, _} =
             Authorization.authorize(MapSet.new([]), "calls.read", {:tenant, "t1"}, %{
               assigned_tenants: %{}
             })
  end

  test "assigned-scope grant is capped by membership access level" do
    grants = MapSet.new(["calls.read", "calls.write"])

    memberships = %{"tenant-a" => :read}

    assert :ok =
             Authorization.authorize(grants, "calls.read", {:tenant, "tenant-a"}, %{
               assigned_tenants: memberships,
               all_tenant_actions: MapSet.new()
             })

    assert {:error, :forbidden} =
             Authorization.authorize(grants, "calls.write", {:tenant, "tenant-a"}, %{
               assigned_tenants: memberships,
               all_tenant_actions: MapSet.new()
             })
  end
end
