defmodule Vxpipe.Persistence.IdentityAuthorizationVersionTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Persistence.{
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentitySessionStore,
    IdentityUserStore
  }

  alias Vxpipe.Persistence.Schema.Tenant

  setup do
    attrs = setup_attrs()

    result =
      case IdentityInstallationStore.fetch() do
        {:ok, %{mode: :first_run}} ->
          IdentityInstallationStore.complete_first_run(attrs)

        {:ok, %{mode: :operator_required}} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)
          IdentityInstallationStore.consume_setup_proof(proof, attrs)
      end

    {:ok, %{user: root}} = result
    {:ok, member_role} = IdentityRoleStore.fetch_by_slug("tenant-member")

    actor = %{
      actor_user_public_id: root.public_id,
      actor_session_public_id: attrs.session_public_id
    }

    {:ok, member} =
      IdentityUserStore.create(
        Map.merge(actor, %{
          public_id: Ecto.UUID.generate(),
          email: "version-member@example.test",
          normalized_email: "version-member@example.test",
          password_hash: "synthetic-member-hash",
          role_public_id: member_role.public_id,
          memberships: %{}
        })
      )

    %{root: root, member: member, actor: actor, attrs: attrs}
  end

  test "authority changes advance the version without reads or email edits advancing it", %{
    member: member,
    actor: actor
  } do
    assert Map.get(member, :authorization_version) == 1

    tenant =
      Repo.insert!(Tenant.changeset(%Tenant{}, %{key: "versiontenant001", name: "Version"}))

    {:ok, role} = IdentityRoleStore.fetch_by_slug("tenant-manager")

    changes = [
      %{memberships: %{tenant.key => :read}},
      %{memberships: %{tenant.key => :read_write}},
      %{role_public_id: role.public_id},
      %{disabled: true},
      %{disabled: false}
    ]

    Enum.reduce(changes, member, fn change, current ->
      attrs =
        actor
        |> Map.merge(change)
        |> Map.put(:expected_current_role_public_id, current.role_public_id)

      assert {:ok, updated} = IdentityUserStore.apply_update(member.public_id, attrs)
      assert updated.authorization_version == current.authorization_version + 1
      assert {:ok, stored} = IdentityUserStore.fetch_by_public_id(member.public_id)
      assert stored.authorization_version == updated.authorization_version
      updated
    end)

    assert {:ok, updated} =
             IdentityUserStore.apply_update(
               member.public_id,
               Map.merge(actor, %{
                 email: "renamed@example.test",
                 normalized_email: "renamed@example.test"
               })
             )

    assert updated.authorization_version == 6
    assert {:ok, fetched} = IdentityUserStore.fetch_by_email("renamed@example.test")
    assert fetched.authorization_version == 6
  end

  test "password changes advance the version and failed proof leaves it unchanged", %{
    member: member
  } do
    assert {:ok, updated} =
             IdentityUserStore.apply_update(member.public_id, %{
               password_hash: "replacement-synthetic-hash",
               expected_current_password_hash: "synthetic-member-hash"
             })

    assert Map.get(updated, :authorization_version) == 2

    assert {:error, :stale_target} =
             IdentityUserStore.apply_update(member.public_id, %{
               password_hash: "another-synthetic-hash",
               expected_current_password_hash: "synthetic-member-hash"
             })

    assert {:ok, stored} = IdentityUserStore.fetch_by_public_id(member.public_id)
    assert stored.authorization_version == 2
  end

  test "failed audit rolls back authority version and status together", %{
    member: member,
    actor: actor
  } do
    assert {:error, :unavailable} =
             IdentityUserStore.apply_update(
               member.public_id,
               Map.merge(actor, %{disabled: true, audit_event: %{action: ""}})
             )

    assert {:ok, stored} = IdentityUserStore.fetch_by_public_id(member.public_id)
    assert Map.get(stored, :authorization_version) == 1
    assert stored.disabled_at == nil
  end

  test "recovery advances the returned and stored version only when the whole recovery commits",
       %{
         root: root,
         attrs: original
       } do
    {:ok, %{proof: proof}} = IdentityInstallationStore.issue_recovery_proof(900)
    attrs = setup_attrs()

    assert {:error, :unavailable} =
             IdentityInstallationStore.consume_recovery_proof(
               proof,
               Map.put(attrs, :audit_event, %{action: ""})
             )

    assert {:ok, unchanged} = IdentityUserStore.fetch_by_public_id(root.public_id)
    assert Map.get(unchanged, :authorization_version) == 1

    assert {:ok, _} =
             IdentitySessionStore.fetch_valid(original.session_digest, DateTime.utc_now())

    assert {:ok, %{user: recovered}} =
             IdentityInstallationStore.consume_recovery_proof(proof, attrs)

    assert recovered.authorization_version == 2
    assert {:ok, stored} = IdentityUserStore.fetch_by_public_id(root.public_id)
    assert stored.authorization_version == 2

    assert {:error, :revoked} =
             IdentitySessionStore.fetch_valid(original.session_digest, DateTime.utc_now())
  end

  defp setup_attrs do
    %{
      user_public_id: Ecto.UUID.generate(),
      email: "version-root@example.test",
      normalized_email: "version-root@example.test",
      password_hash: "synthetic-root-hash",
      session_public_id: Ecto.UUID.generate(),
      session_digest: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
      session_expires_at: DateTime.add(DateTime.utc_now(), 3600)
    }
  end
end
