defmodule Vxpipe.Persistence.DiagnosticsSettingsStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Identity.{DiagnosticsSettings, Principal}
  alias Vxpipe.CallEngine.Diagnostics.{SettingsProjection, SettingsSupervisor}
  alias Vxpipe.Persistence.DiagnosticsSettingsStore
  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentitySession, IdentityUser, UserAccessEvent}

  test "migration defaults off; both built-in operator roles can read persisted settings" do
    for kind <- [:admin, :superadmin] do
      actor = actor(kind)

      assert {:ok, %{enabled: false, revision: 0, updated_at: nil, updated_by: nil}} =
               DiagnosticsSettings.fetch(deps(), actor)
    end

    assert {:ok, %{enabled: false, revision: 0}} = DiagnosticsSettingsStore.snapshot()
  end

  test "runtime projection follows durable operator revisions through the snapshot port" do
    parent = self()
    clock = :atomics.new(1, signed: true)
    projection = __MODULE__.Projection
    reader = __MODULE__.Reader

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Pool,
       projection: projection,
       reader: reader,
       loader: fn ->
         result = DiagnosticsSettingsStore.snapshot()
         send(parent, :snapshot_read)
         result
       end,
       clock: fn -> :atomics.get(clock, 1) end,
       send_after: fn target, message, delay ->
         send(parent, {:scheduled, target, message, delay})
         make_ref()
       end}
    )

    settle_projection(reader, projection)
    assert {:disabled, 0} = SettingsProjection.status(projection)
    actor = actor(:admin)

    for {enabled, revision} <- [{true, 1}, {false, 2}] do
      assert {:ok, %{revision: ^revision}} =
               DiagnosticsSettings.update(deps(), actor, enabled, revision - 1)

      :atomics.put(clock, 1, revision * 1_000)
      assert_receive {:scheduled, target, {:poll, _} = poll, 1_000}
      send(target, poll)
      settle_projection(reader, projection)
      expected = if enabled, do: :enabled, else: :disabled
      assert {^expected, ^revision} = SettingsProjection.status(projection)
    end
  end

  test "save persists revision and actor with one audit; no-op retries preserve revision" do
    actor = actor(:admin)
    assert {:ok, saved} = DiagnosticsSettings.update(deps(), actor, true, 0)
    assert saved.enabled and saved.revision == 1
    assert saved.updated_by == actor.user_public_id
    assert %DateTime{} = saved.updated_at
    assert {:ok, ^saved} = DiagnosticsSettings.fetch(deps(), actor)
    assert {:ok, ^saved} = DiagnosticsSettings.update(deps(), actor, true, 1)
    assert {:error, :conflict} = DiagnosticsSettings.update(deps(), actor, true, 0)
    assert {:error, :conflict} = DiagnosticsSettings.update(deps(), actor, false, 0)

    [event] =
      Repo.all(from(e in UserAccessEvent, where: e.action == "diagnostics_settings_updated"))

    assert event.summary == %{"enabled" => true, "revision" => 1}
    user = Repo.get_by!(IdentityUser, public_id: actor.user_public_id)
    assert event.actor_user_id == user.id
    assert {:ok, %{enabled: true, revision: 1}} = DiagnosticsSettingsStore.snapshot()

    assert {:ok, %{enabled: false, revision: 2}} =
             DiagnosticsSettings.update(deps(), actor, false, 1)
  end

  test "stored demotion and custom roles defeat stale or fabricated admin claims" do
    for kind <- [:member, :custom] do
      actor = actor(kind)
      forged = %{actor | account_kind: :admin}
      assert {:error, :forbidden} = DiagnosticsSettingsStore.fetch(forged)
      assert {:error, :forbidden} = DiagnosticsSettingsStore.update(forged, true, 0)
    end

    actor = actor(:admin)
    member = Repo.get_by!(IdentityRole, slug: "diag-member")

    Repo.update_all(from(u in IdentityUser, where: u.public_id == ^actor.user_public_id),
      set: [role_id: member.id]
    )

    assert {:error, :forbidden} = DiagnosticsSettingsStore.update(actor, true, 0)
    assert {:ok, %{enabled: false, revision: 0}} = DiagnosticsSettingsStore.snapshot()
  end

  test "revoked, expired, foreign and disabled sessions fail on reads and direct writes" do
    for fault <- [:revoked, :expired, :foreign, :disabled] do
      actor = actor(:admin)
      session = Repo.get_by!(IdentitySession, public_id: actor.session_public_id)

      case fault do
        :revoked ->
          Repo.update!(Ecto.Changeset.change(session, revoked_at: DateTime.utc_now()))

        :expired ->
          Repo.update!(
            Ecto.Changeset.change(session,
              issued_at: DateTime.add(DateTime.utc_now(), -120),
              expires_at: DateTime.add(DateTime.utc_now(), -60)
            )
          )

        :foreign ->
          other = actor(:admin)
          user = Repo.get_by!(IdentityUser, public_id: other.user_public_id)
          Repo.update!(Ecto.Changeset.change(session, user_id: user.id))

        :disabled ->
          user = Repo.get_by!(IdentityUser, public_id: actor.user_public_id)
          Repo.update!(Ecto.Changeset.change(user, disabled_at: DateTime.utc_now()))
      end

      assert {:error, :forbidden} = DiagnosticsSettingsStore.fetch(actor)
      assert {:error, :forbidden} = DiagnosticsSettingsStore.update(actor, true, 0)
    end
  end

  test "adapter independently rejects malformed values and nonbrowser authority" do
    actor = actor(:admin)
    assert {:error, :invalid_enabled} = DiagnosticsSettingsStore.update(actor, "true", 0)
    assert {:error, :invalid_revision} = DiagnosticsSettingsStore.update(actor, true, -1)

    assert {:error, :forbidden} =
             DiagnosticsSettingsStore.fetch(%{actor | credential_kind: :oauth})

    assert {:error, :forbidden} =
             DiagnosticsSettingsStore.update(%{actor | credential_kind: :oauth}, true, 0)

    assert {:ok, %{enabled: false, revision: 0}} = DiagnosticsSettingsStore.snapshot()
  end

  test "audit insertion failure rolls back the setting and its revision" do
    actor = actor(:admin)

    Repo.query!(
      "ALTER TABLE user_access_events ADD CONSTRAINT reject_diagnostics_test CHECK (action <> 'diagnostics_settings_updated')"
    )

    assert {:error, :unavailable} = DiagnosticsSettings.update(deps(), actor, true, 0)
    assert {:ok, %{enabled: false, revision: 0}} = DiagnosticsSettingsStore.snapshot()

    assert [] ==
             Repo.all(
               from(e in UserAccessEvent, where: e.action == "diagnostics_settings_updated")
             )
  end

  test "missing singleton is unavailable and never recreated by a read or write" do
    actor = actor(:admin)
    Repo.query!("DELETE FROM installation_diagnostics_settings")
    assert {:error, :unavailable} = DiagnosticsSettingsStore.snapshot()
    assert {:error, :unavailable} = DiagnosticsSettingsStore.fetch(actor)
    assert {:error, :unavailable} = DiagnosticsSettingsStore.update(actor, true, 0)
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM installation_diagnostics_settings")
  end

  defp deps, do: %{diagnostics_settings: DiagnosticsSettingsStore}

  defp settle_projection(reader, projection) do
    assert_receive :snapshot_read
    _ = :sys.get_state(reader)
    _ = :sys.get_state(projection)
  end

  defp actor(kind) do
    slug = "diag-#{kind}"

    role =
      if kind in [:admin, :superadmin],
        do: Repo.get_by!(IdentityRole, kind: Atom.to_string(kind)),
        else:
          Repo.get_by(IdentityRole, slug: slug) ||
            Repo.insert!(
              IdentityRole.ordinary_changeset(%IdentityRole{}, %{
                public_id: Ecto.UUID.generate(),
                slug: slug,
                name: slug
              })
            )

    id = Ecto.UUID.generate()

    user =
      Repo.insert!(
        IdentityUser.changeset(%IdentityUser{}, %{
          public_id: id,
          email: "#{id}@example.test",
          normalized_email: "#{id}@example.test",
          password_hash: "synthetic",
          role_id: role.id
        })
      )

    now = DateTime.utc_now()

    session =
      Repo.insert!(
        IdentitySession.changeset(%IdentitySession{}, %{
          public_id: Ecto.UUID.generate(),
          user_id: user.id,
          token_digest: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
          issued_at: now,
          expires_at: DateTime.add(now, 600)
        })
      )

    struct(Principal,
      account_kind: kind,
      user_public_id: user.public_id,
      session_public_id: session.public_id,
      role_public_id: role.public_id,
      role_revision: role.revision
    )
  end
end
