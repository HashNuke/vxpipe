defmodule Vxpipe.Identity.ActorEnforcementTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.{Accounts, Roles}

  defp super_grants do
    MapSet.new([
      "users.read",
      "users.members.write",
      "users.admins.write",
      "users.superadmins.write"
    ])
  end

  defp deps do
    %{
      users: Vxpipe.Identity.FakeUsers,
      roles: Vxpipe.Identity.FakeRoles,
      hasher: Vxpipe.Identity.FakeHasher,
      uuid: Vxpipe.Identity.FakeUuid,
      audit: Vxpipe.Identity.Accounts.NoopAudit
    }
  end

  defp role_deps do
    %{
      roles: Vxpipe.Identity.FakeRoles,
      audit: Vxpipe.Identity.Accounts.NoopAudit,
      uuid: Vxpipe.Identity.FakeUuid
    }
  end

  defp valid_uuid, do: Vxpipe.Identity.Uuid.generate()

  test "create_user rejects nil actor id" do
    actor = %{
      user_public_id: nil,
      session_public_id: valid_uuid(),
      grants: super_grants(),
      account_kind: :superadmin
    }

    assert {:error, :forbidden} =
             Accounts.create_user(deps(), actor, %{
               email: "new@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })
  end

  test "create_user rejects non-UUID placeholder actor" do
    actor = %{
      user_public_id: "setup",
      session_public_id: valid_uuid(),
      grants: super_grants(),
      account_kind: :superadmin
    }

    assert {:error, :forbidden} =
             Accounts.create_user(deps(), actor, %{
               email: "new@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })
  end

  test "create_user rejects missing session" do
    actor = %{user_public_id: valid_uuid(), grants: super_grants(), account_kind: :superadmin}

    assert {:error, :forbidden} =
             Accounts.create_user(deps(), actor, %{
               email: "new@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })
  end

  test "create_user rejects malformed session" do
    actor = %{
      user_public_id: valid_uuid(),
      session_public_id: "not-a-uuid",
      grants: super_grants(),
      account_kind: :superadmin
    }

    assert {:error, :forbidden} =
             Accounts.create_user(deps(), actor, %{
               email: "new@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })
  end

  test "create_role rejects placeholder actor without session" do
    actor = %{user_public_id: "s", grants: MapSet.new(["users.read"]), account_kind: :superadmin}

    assert {:error, :forbidden} =
             Roles.create_role(role_deps(), actor, %{
               name: "Custom",
               slug: "custom-actor",
               grants: []
             })
  end
end
