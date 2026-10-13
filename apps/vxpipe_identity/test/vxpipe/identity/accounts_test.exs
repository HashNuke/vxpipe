defmodule Vxpipe.Identity.AccountsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.Accounts

  defp superadmin_actor do
    %{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      grants:
        MapSet.new([
          "users.read",
          "users.members.write",
          "users.admins.write",
          "users.superadmins.write"
        ]),
      account_kind: :superadmin
    }
  end

  defp admin_actor do
    %{
      user_public_id: "33333333-3333-4333-8333-333333333333",
      session_public_id: "44444444-4444-4444-8444-444444444444",
      grants: MapSet.new(["users.read", "users.members.write"]),
      account_kind: :admin
    }
  end

  defp deps(overrides \\ %{}) do
    Map.merge(
      %{
        users: Vxpipe.Identity.FakeUsers,
        roles: Vxpipe.Identity.FakeRoles,
        hasher: Vxpipe.Identity.FakeHasher,
        uuid: Vxpipe.Identity.FakeUuid,
        audit: Vxpipe.Identity.Accounts.NoopAudit
      },
      overrides
    )
  end

  test "superadmin can create ordinary user; hashes password and strips hash in response" do
    assert {:ok, user} =
             Accounts.create_user(deps(), superadmin_actor(), %{
               email: "  New@Example.com ",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })

    assert user.normalized_email == "new@example.com"
    refute Map.has_key?(user, :password_hash)
  end

  test "admin cannot create admin target" do
    assert {:error, :forbidden} =
             Accounts.create_user(deps(), admin_actor(), %{
               email: "boss@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-admin",
               memberships: %{}
             })
  end

  test "admin can create ordinary member; cannot create superadmin" do
    assert {:ok, user} =
             Accounts.create_user(deps(), admin_actor(), %{
               email: "ordinary@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })

    assert user.normalized_email == "ordinary@example.com"

    assert {:error, :forbidden} =
             Accounts.create_user(deps(), admin_actor(), %{
               email: "root2@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-superadmin",
               memberships: %{}
             })
  end

  defmodule FailingAudit do
    @behaviour Vxpipe.Identity.Ports.Audit
    @impl true
    def append(_), do: {:error, :unavailable}
  end

  test "audit failure fails user creation" do
    assert {:error, :unavailable} =
             Accounts.create_user(deps(%{audit: FailingAudit}), superadmin_actor(), %{
               email: "audit@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })
  end

  test "confirmation mismatch changes nothing" do
    assert {:error, :confirmation_mismatch} =
             Accounts.create_user(deps(), superadmin_actor(), %{
               email: "new@example.com",
               password: "correct horse 15!",
               password_confirmation: "different horse 15!",
               role_public_id: "role-member",
               memberships: %{}
             })
  end

  test "directory reads require users.read" do
    actor = %{user_public_id: "u", grants: MapSet.new([]), account_kind: :member}
    assert {:error, :forbidden} = Accounts.list_users(deps(), actor, %{})
  end

  test "stale role expectation is rejected as forbidden" do
    assert {:error, :forbidden} =
             Accounts.update_user(
               deps(%{users: Vxpipe.Identity.FakeMemberUsers}),
               superadmin_actor(),
               "user-1",
               %{
                 email: "new@example.com",
                 expected_current_role_public_id: "stale-role-id"
               }
             )

    assert {:error, {:not_found, "user-1"}} =
             Accounts.update_user(
               deps(%{users: Vxpipe.Identity.FakeMemberUsers}),
               superadmin_actor(),
               "user-1",
               %{
                 email: "new@example.com",
                 expected_current_role_public_id: "role-member"
               }
             )
  end
end
