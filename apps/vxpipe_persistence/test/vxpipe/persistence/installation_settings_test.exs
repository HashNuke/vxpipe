defmodule Vxpipe.Persistence.InstallationSettingsTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Identity.{Bootstrap, InstallationSettings, Sessions}
  alias Vxpipe.Persistence.{IdentityInstallationStore, Schema.AuthenticationInstallation}

  defp deps do
    %{
      installations: IdentityInstallationStore,
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }
  end

  defp setup_account(url) do
    Repo.update_all(AuthenticationInstallation,
      set: [bootstrap_mode: "first_run", setup_completed_at: nil, initial_superadmin_user_id: nil]
    )

    Bootstrap.complete_first_run(
      deps(),
      "installation-owner@example.test",
      "example password 15!",
      "example password 15!",
      %{public_url: url}
    )
  end

  test "setup persists its normalized origin atomically with the first account" do
    assert {:ok, %{token: token}} = setup_account("https://CALLS.example.test:8443/setup?q=1#top")
    assert {:ok, actor} = Sessions.authenticate(deps(), token)

    assert {:ok, %{public_url: "https://calls.example.test:8443", revision: 1}} =
             InstallationSettings.fetch(deps(), actor)

    assert {:error, :invalid_public_url} = setup_account("http://insecure.example.test")
    assert {:ok, :pending_first_run} = Bootstrap.status(deps())
  end

  test "only current Superadmin sessions can change the URL and stale saves fail" do
    assert {:ok, %{token: token}} = setup_account("https://old.example.test")
    assert {:ok, actor} = Sessions.authenticate(deps(), token)

    assert {:error, :forbidden} =
             InstallationSettings.fetch(deps(), %{actor | account_kind: :admin})

    assert {:error, :forbidden} =
             InstallationSettings.update(
               deps(),
               %{actor | account_kind: :member},
               "https://new.example.test",
               1
             )

    assert {:ok, %{public_url: "https://new.example.test", revision: 2}} =
             InstallationSettings.update(deps(), actor, "https://new.example.test/path", 1)

    assert {:error, :conflict} =
             InstallationSettings.update(deps(), actor, "https://stale.example.test", 1)

    assert :ok = Sessions.logout(deps(), token)

    assert {:error, :forbidden} =
             InstallationSettings.update(deps(), actor, "https://revoked.example.test", 2)

    assert {:ok, %{public_url: "https://new.example.test", public_url_revision: 2}} =
             IdentityInstallationStore.fetch()
  end
end
