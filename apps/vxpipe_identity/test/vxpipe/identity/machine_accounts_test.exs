defmodule Vxpipe.Identity.MachineAccountsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.{Accounts, ApiKeyActor, Roles}
  @key "11111111-1111-4111-8111-111111111111"

  test "machine account authority stamps key audit identity without user/session claims" do
    {:ok, actor} = ApiKeyActor.new(@key)

    for role <- ["role-member", "role-admin", "role-superadmin"] do
      assert {:ok, user} =
               Accounts.create_user(deps(), actor, %{
                 email: "new@example.test",
                 password: "correct horse 15!",
                 password_confirmation: "correct horse 15!",
                 role_public_id: role,
                 memberships: %{},
                 actor_user_public_id: "spoof",
                 actor_api_key_public_id: "spoof"
               })

      assert_received {:created, attrs}
      assert attrs.actor_api_key_public_id == @key
      assert attrs.audit_event.actor_api_key_public_id == @key
      refute Map.has_key?(attrs, :actor_user_public_id)
      refute Map.has_key?(attrs, :actor_session_public_id)
      refute Map.has_key?(user, :password_hash)
    end

    assert {:error, :forbidden} =
             Accounts.reset_password(
               deps(),
               actor,
               "user",
               "correct horse 15!",
               "correct horse 15!"
             )

    assert {:error, :forbidden} = Roles.create_role(deps(), actor, %{})

    assert {:error, :forbidden} =
             Accounts.update_user(deps(), actor, "user", %{password_hash: "forged"})
  end

  test "partial updates keep omitted status and memberships and override forged actor fields" do
    {:ok, actor} = ApiKeyActor.new(@key)

    assert {:ok, _} =
             Accounts.update_user(deps(), actor, "user", %{
               "actor_api_key_public_id" => "spoof",
               email: "changed@example.test",
               actor_user_public_id: "spoof",
               actor_session_public_id: "spoof"
             })

    assert_received {:updated, changes}
    assert changes.actor_api_key_public_id == @key
    assert changes.audit_event.actor_api_key_public_id == @key
    refute Map.has_key?(changes, :disabled)
    refute Map.has_key?(changes, :memberships)
    refute Map.has_key?(changes, :actor_user_public_id)
    refute Map.has_key?(changes, :actor_session_public_id)
    refute Map.has_key?(changes, "actor_api_key_public_id")
  end

  test "machine directories use bounded queries and reject out-of-range pages" do
    {:ok, actor} = ApiKeyActor.new(@key)

    assert {:ok, %{users: [], total: 0, total_pages: 0, page_size: 25}} =
             Accounts.list_users(deps(), actor, %{})

    assert_received {:listed, %{page: 1, page_size: 25}}
    assert {:error, :page_out_of_range} = Accounts.list_users(deps(), actor, %{page: 2})
    assert {:error, :invalid_pagination} = Accounts.list_users(deps(), actor, %{page_size: 51})

    assert {:error, :invalid_search} =
             Accounts.list_users(deps(), actor, %{search: String.duplicate("x", 121)})

    assert {:ok, %{roles: [], total: 0, total_pages: 0}} =
             Roles.list_role_options(deps(), actor, %{})

    assert_received {:role_options, %{page: 1, page_size: 25}}

    for unsupported <- [%{search: "admin"}, %{role_public_id: @key}, %{other: true}] do
      assert {:error, :invalid_pagination} = Roles.list_role_options(deps(), actor, unsupported)
    end

    assert {:error, :forbidden} = ApiKeyActor.new("bad")
    assert {:error, :forbidden} = Accounts.list_users(deps(), %{api_key_id: @key}, %{})
  end

  def create(attrs) do
    send(self(), {:created, attrs})
    {:ok, %{public_id: "user", password_hash: attrs.password_hash}}
  end

  def fetch_by_public_id("user"),
    do:
      {:ok,
       %{
         public_id: "user",
         role_public_id: "role-member",
         role_kind: :member,
         memberships: %{},
         disabled_at: ~U[2026-10-15 00:00:00Z]
       }}

  def apply_update(_id, changes) do
    send(self(), {:updated, changes})
    {:ok, %{public_id: "user"}}
  end

  def list(filters) do
    send(self(), {:listed, filters})
    {:ok, %{users: [], total: 0}}
  end

  def list_options(filters) do
    send(self(), {:role_options, filters})
    {:ok, %{roles: [], total: 0}}
  end

  def fetch(id), do: Vxpipe.Identity.FakeRoles.fetch(id)

  defp deps,
    do: %{
      users: __MODULE__,
      roles: __MODULE__,
      hasher: Vxpipe.Identity.FakeHasher,
      uuid: Vxpipe.Identity.FakeUuid,
      audit: Vxpipe.Identity.Accounts.NoopAudit
    }
end
