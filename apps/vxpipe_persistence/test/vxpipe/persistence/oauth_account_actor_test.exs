defmodule Vxpipe.Persistence.OAuthAccountActorTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Identity.{Accounts, Principal}
  alias Vxpipe.Identity.OAuth.Delegation
  alias Vxpipe.Persistence.{IdentityRoleStore, IdentityUserStore, OAuthFixtures}
  alias Vxpipe.Persistence.OAuth.{Grant, Store}
  alias Vxpipe.Persistence.Schema.{IdentityRole, UserAccessEvent}

  setup do
    root = OAuthFixtures.browser_user()
    member = create_user(root.principal, "tenant-member")
    %{root: root, member: member}
  end

  test "account writes preserve delegated user and grant attribution", %{
    root: root,
    member: member
  } do
    {actor, _token} = oauth_actor(root.principal)

    assert {:ok, updated} =
             Accounts.update_user(deps(), actor, member.public_id, %{disabled: true})

    assert updated.disabled_at != nil

    event =
      Repo.get_by!(UserAccessEvent,
        action: "user_updated",
        target_user_id: user_id(member.public_id)
      )

    assert event.actor_user_id == root.user.id
    assert Map.get(event, :actor_oauth_grant_public_id) == actor.oauth_grant_public_id
    assert event.actor_api_key_id == nil
  end

  test "revoked grants fail inside the mutation even with a previously authenticated principal",
       %{root: root, member: member} do
    {actor, token} = oauth_actor(root.principal)
    grant = Repo.get!(Grant, actor.oauth_grant_public_id)

    assert :ok =
             Store.revoke(
               %{"client_id" => grant.client_id, "token" => token.access_token},
               OAuthFixtures.resource()
             )

    assert {:error, :forbidden} =
             Accounts.update_user(deps(), actor, member.public_id, %{disabled: true})

    assert {:ok, unchanged} = IdentityUserStore.fetch_by_public_id(member.public_id)
    assert unchanged.disabled_at == nil
  end

  test "Admin OAuth can manage ordinary users but cannot mutate privileged users", %{
    root: root,
    member: member
  } do
    admin = create_user(root.principal, "admin")

    {:ok, session} =
      Vxpipe.Persistence.IdentitySessionStore.create(%{
        public_id: Ecto.UUID.generate(),
        user_public_id: admin.public_id,
        digest: String.duplicate("f", 64),
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      })

    {:ok, role} = IdentityRoleStore.fetch(admin.role_public_id)
    {:ok, browser} = Principal.for_session(admin, role, session)
    {actor, _} = oauth_actor(browser)

    assert {:ok, _} = Accounts.update_user(deps(), actor, member.public_id, %{disabled: true})

    assert {:error, :forbidden} =
             Accounts.update_user(deps(), actor, root.user.public_id, %{disabled: true})

    attrs = %{
      actor_user_public_id: admin.public_id,
      actor_oauth_grant_public_id: actor.oauth_grant_public_id,
      disabled: true
    }

    assert {:error, :forbidden} = IdentityUserStore.apply_update(root.user.public_id, attrs)
  end

  test "current permissions and approved ceiling are rechecked inside account writes", %{
    root: root,
    member: member
  } do
    {actor, _} = oauth_actor(root.principal)
    grant = Repo.get!(Grant, actor.oauth_grant_public_id)
    authority = Map.put(grant.authority, "grants", ["users.read"])
    Repo.update!(Ecto.Changeset.change(grant, authority: authority))

    assert {:error, :forbidden} =
             Accounts.update_user(deps(), actor, member.public_id, %{disabled: true})

    assert {:ok, unchanged} = IdentityUserStore.fetch_by_public_id(member.public_id)
    assert unchanged.disabled_at == nil
  end

  defp oauth_actor(browser) do
    {:ok, client} = Store.register_client(OAuthFixtures.registration())
    {:ok, snapshot} = Store.consent_snapshot(browser)

    {:ok, issued} =
      Store.issue_code(
        browser,
        OAuthFixtures.authorization(client.client_id),
        OAuthFixtures.resource(),
        snapshot
      )

    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    {:ok, identity} = Store.authenticate(token.access_token, OAuthFixtures.resource())
    {:ok, actor} = Delegation.principal(identity.user, identity.role, identity.grant)
    {actor, token}
  end

  defp create_user(actor, slug) do
    role = Repo.get_by!(IdentityRole, slug: slug)
    public_id = Ecto.UUID.generate()

    {:ok, user} =
      IdentityUserStore.create(%{
        public_id: public_id,
        email: "#{public_id}@example.test",
        normalized_email: "#{public_id}@example.test",
        password_hash: "synthetic-hash",
        role_public_id: role.public_id,
        memberships: %{},
        actor_user_public_id: actor.user_public_id,
        actor_session_public_id: actor.session_public_id
      })

    user
  end

  defp deps, do: %{users: IdentityUserStore, roles: IdentityRoleStore}

  defp user_id(public_id),
    do: Repo.get_by!(Vxpipe.Persistence.Schema.IdentityUser, public_id: public_id).id
end
