defmodule Vxpipe.Persistence.InstallationURLCacheTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Identity.{Bootstrap, InstallationSettings, InstallationURLCache, Sessions}
  alias Vxpipe.Persistence.{IdentityInstallationStore, Schema.AuthenticationInstallation}

  @cache __MODULE__.Cache
  @tasks __MODULE__.Tasks

  setup do
    previous = Application.get_env(:vxpipe_identity, :dependencies)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:vxpipe_identity, :dependencies, previous),
        else: Application.delete_env(:vxpipe_identity, :dependencies)
    end)

    deps = %{
      installations: IdentityInstallationStore,
      installation_url_cache: @cache,
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }

    Application.put_env(:vxpipe_identity, :dependencies, deps)

    Repo.update_all(AuthenticationInstallation,
      set: [
        bootstrap_mode: "first_run",
        setup_completed_at: nil,
        initial_superadmin_user_id: nil,
        public_url: nil,
        public_url_revision: 0
      ]
    )

    start_supervised!({Task.Supervisor, name: @tasks})
    owner = self()

    start_supervised!(
      {InstallationURLCache,
       name: @cache,
       task_supervisor: @tasks,
       loader: fn ->
         send(owner, :cache_database_read)
         IdentityInstallationStore.fetch()
       end}
    )

    %{deps: deps}
  end

  test "the public URL accessor caches reads and setup/save invalidate only after success", %{
    deps: deps
  } do
    assert {:ok, nil} = InstallationSettings.public_url()
    assert_receive :cache_database_read
    for _ <- 1..10, do: assert({:ok, nil} = InstallationSettings.public_url())
    refute_received :cache_database_read

    assert {:ok, %{token: token}} =
             Bootstrap.complete_first_run(
               deps,
               "cache-owner@example.test",
               "example password 15!",
               "example password 15!",
               %{public_url: "https://first.example.test"}
             )

    assert {:ok, "https://first.example.test"} = InstallationSettings.public_url()
    assert_receive :cache_database_read
    assert {:ok, actor} = Sessions.authenticate(deps, token)

    assert {:ok, %{revision: 2}} =
             InstallationSettings.update(deps, actor, "https://second.example.test", 1)

    assert {:ok, "https://second.example.test"} = InstallationSettings.public_url()
    assert_receive :cache_database_read

    assert {:error, :conflict} =
             InstallationSettings.update(deps, actor, "https://stale.example.test", 1)

    assert {:ok, "https://second.example.test"} = InstallationSettings.public_url()
    refute_received :cache_database_read
  end

  test "a committed setting is still reported as saved if the local cache is unavailable", %{
    deps: deps
  } do
    assert {:ok, %{token: token}} =
             Bootstrap.complete_first_run(
               deps,
               "cache-owner@example.test",
               "example password 15!",
               "example password 15!",
               %{public_url: "https://first.example.test"}
             )

    assert {:ok, actor} = Sessions.authenticate(deps, token)
    stop_supervised!(InstallationURLCache)

    assert {:ok, %{revision: 2}} =
             InstallationSettings.update(deps, actor, "https://second.example.test", 1)

    assert {:error, :unavailable} = InstallationSettings.public_url()
    assert {:ok, %{public_url: "https://second.example.test"}} = IdentityInstallationStore.fetch()
  end
end
