defmodule Vxpipe.Identity.RolesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Roles

  defp superadmin,
    do: %{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      grants: MapSet.new(["users.read"]),
      account_kind: :superadmin
    }

  defp member,
    do: %{
      user_public_id: "33333333-3333-4333-8333-333333333333",
      session_public_id: "44444444-4444-4444-8444-444444444444",
      grants: MapSet.new([]),
      account_kind: :member
    }

  defp deps,
    do: %{
      roles: Vxpipe.Identity.FakeRoles,
      audit: Vxpipe.Identity.Accounts.NoopAudit,
      uuid: Vxpipe.Identity.FakeUuid
    }

  test "Services read can cover narrower service and credential writes" do
    assert {:ok, role} = Roles.create_role(deps(), superadmin(), %{
      name: "Credential manager", slug: "credential-manager", description: "Discard this",
      grants: [%{permission: "tenant_services.read", scope: :all_tenants},
        %{permission: "tenant_services.write", scope: :assigned_tenants},
        %{permission: "tenant_api_keys.write", scope: :assigned_tenants}]
    })
    refute Map.has_key?(role, :description)
    assert {:error, {:missing_prerequisite, "tenant_services.read"}} = Roles.create_role(deps(), superadmin(), %{
      name: "Invalid", slug: "invalid", grants: [%{permission: "tenant_services.read", scope: :assigned_tenants},
        %{permission: "tenant_api_keys.write", scope: :all_tenants}]
    })
  end

  test "ordinary users cannot create roles" do
    assert {:error, :forbidden} =
             Roles.create_role(deps(), member(), %{name: "Custom", slug: "custom", grants: []})
  end

  test "rejects reserved user-write grants in ordinary roles" do
    assert {:error, :reserved_permission} =
             Roles.create_role(deps(), superadmin(), %{
               name: "Sneaky",
               slug: "sneaky",
               grants: [%{permission: "users.members.write", scope: :installation}]
             })
  end

  test "rejects unknown permissions and missing prerequisites" do
    assert {:error, :unknown_permission} =
             Roles.create_role(deps(), superadmin(), %{
               name: "X",
               slug: "x-role",
               grants: [%{permission: "nope.deny", scope: :installation}]
             })

    assert {:error, {:missing_prerequisite, "calls.read"}} =
             Roles.create_role(deps(), superadmin(), %{
               name: "Writer",
               slug: "writer",
               grants: [%{permission: "calls.write", scope: :assigned_tenants}]
             })
  end

  test "rejects write without same-scope read and duplicate permission across scopes" do
    assert {:error, {:missing_prerequisite, "calls.read"}} =
             Roles.create_role(deps(), superadmin(), %{
               name: "CrossScope",
               slug: "cross-scope",
               grants: [
                 %{permission: "calls.read", scope: :all_tenants},
                 %{permission: "calls.write", scope: :assigned_tenants}
               ]
             })

    assert {:error, :overlapping_scopes} =
             Roles.create_role(deps(), superadmin(), %{
               name: "DupKey",
               slug: "dup-key",
               grants: [
                 %{permission: "calls.read", scope: :all_tenants},
                 %{permission: "calls.read", scope: :assigned_tenants}
               ]
             })
  end

  test "accepts valid ordinary role with read+write pair" do
    assert {:ok, role} =
             Roles.create_role(deps(), superadmin(), %{
               name: "Caller",
               slug: "caller",
               grants: [
                 %{permission: "calls.read", scope: :assigned_tenants},
                 %{permission: "calls.write", scope: :assigned_tenants}
               ]
             })

    assert role.kind == nil
  end

  test "built-in effective grants cover builtin_grants set" do
    for kind <- [:superadmin, :admin] do
      defs = Vxpipe.Identity.Permission.builtin_grant_defs(kind)
      keys = MapSet.new(defs, & &1.permission)
      assert keys == Vxpipe.Identity.Permission.builtin_grants(kind)

      for %{permission: perm, scope: scope} <- defs do
        assert {:ok, entry} = Vxpipe.Identity.Permission.fetch(perm)
        assert scope in entry.scopes
      end
    end
  end

  defmodule FailingAudit do
    @behaviour Vxpipe.Identity.Ports.Audit
    @impl true
    def append(_), do: {:error, :unavailable}
  end

  test "audit failure fails role creation" do
    deps = Map.put(deps(), :audit, FailingAudit)

    assert {:error, :unavailable} =
             Roles.create_role(deps, superadmin(), %{
               name: "AuditFail",
               slug: "audit-fail",
               grants: [%{permission: "calls.read", scope: :assigned_tenants}]
             })
  end
end
