defmodule Vxpipe.Persistence.Integration.OAuthExchangeTransactionTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Persistence.{IdentityUserStore, OAuthFixtures, Repo}
  alias Vxpipe.Persistence.OAuth.{Client, Code, Grant, Store, Token}
  alias Vxpipe.Persistence.Schema.{AuthenticationInstallation, IdentityUser}

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    installation = Repo.get!(AuthenticationInstallation, "default")
    %{user: user, principal: principal} = OAuthFixtures.browser_user()
    {:ok, client} = Store.register_client(OAuthFixtures.registration())
    {:ok, snapshot} = Store.consent_snapshot(principal)

    {:ok, issued} =
      Store.issue_code(
        principal,
        OAuthFixtures.authorization(client.client_id),
        OAuthFixtures.resource(),
        snapshot
      )

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(c in Client, where: c.public_id == ^client.client_id))

      Repo.get!(AuthenticationInstallation, "default")
      |> Ecto.Changeset.change(
        setup_completed_at: installation.setup_completed_at,
        initial_superadmin_user_id: installation.initial_superadmin_user_id
      )
      |> Repo.update!()

      Repo.delete_all(from(u in IdentityUser, where: u.id == ^user.id))
      Sandbox.checkin(Repo)
    end)

    %{client: client, issued: issued, user: user, principal: principal, snapshot: snapshot}
  end

  test "two database connections cannot both consume one authorization code", %{
    client: client,
    issued: issued
  } do
    results = race(OAuthFixtures.exchange(client.client_id, issued.code))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :invalid_grant}, &1)) == 1
    assert Repo.aggregate(from(t in Token, where: t.grant_id == ^issued.grant_id), :count) == 1
  end

  test "concurrent refresh replay revokes the winner's successor", %{
    client: client,
    issued: issued
  } do
    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    results = race(OAuthFixtures.refresh(client.client_id, token.refresh_token))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :invalid_grant}, &1)) == 1
    {:ok, successor} = Enum.find(results, &match?({:ok, _}, &1))

    assert {:error, :invalid_token} =
             Store.authenticate(successor.access_token, OAuthFixtures.resource())
  end

  test "grant use waits for the identity installation mutation lock before loading authority", %{
    client: client,
    issued: issued
  } do
    {:ok, token} =
      Store.exchange(
        OAuthFixtures.exchange(client.client_id, issued.code),
        OAuthFixtures.resource()
      )

    observer = self()

    assert {:ok, {worker, monitor}} =
             Repo.transaction(fn ->
               Repo.one!(
                 from(i in AuthenticationInstallation,
                   where: i.key == "default",
                   lock: "FOR UPDATE"
                 )
               )

               worker =
                 start_supervised!(
                   {Task,
                    fn ->
                      :ok = Sandbox.checkout(Repo, sandbox: false)
                      %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
                      send(observer, {:auth_started, self(), connection})
                      result = Store.authenticate(token.access_token, OAuthFixtures.resource())
                      send(observer, {:authenticated, self(), result})
                      Sandbox.checkin(Repo)
                    end}
                 )

               monitor = Process.monitor(worker)
               assert_receive {:auth_started, ^worker, connection}, 5_000
               assert_blocked(connection, System.monotonic_time(:millisecond) + 1_500)
               {worker, monitor}
             end)

    assert_receive {:authenticated, ^worker, {:ok, _}}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000
  end

  test "identity mutations wait for the shared installation lock used by OAuth", %{user: user} do
    observer = self()

    assert {:ok, {worker, monitor}} =
             Repo.transaction(fn ->
               Repo.one!(
                 from(i in AuthenticationInstallation,
                   where: i.key == "default",
                   lock: "FOR SHARE"
                 )
               )

               worker =
                 start_supervised!(
                   {Task,
                    fn ->
                      :ok = Sandbox.checkout(Repo, sandbox: false)
                      %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
                      send(observer, {:mutation_started, self(), connection})

                      result =
                        IdentityUserStore.apply_update(user.public_id, %{
                          password_hash: "replacement-synthetic-hash",
                          expected_current_password_hash: "synthetic-oauth-hash"
                        })

                      send(observer, {:mutated, self(), result})
                      Sandbox.checkin(Repo)
                    end}
                 )

               monitor = Process.monitor(worker)
               assert_receive {:mutation_started, ^worker, connection}, 5_000
               assert_blocked(connection, System.monotonic_time(:millisecond) + 1_500)
               {worker, monitor}
             end)

    assert_receive {:mutated, ^worker, {:ok, %{authorization_version: 2}}}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000
  end

  test "unused-client cleanup cannot cascade-delete a concurrently approved grant", ctx do
    Repo.delete_all(from(g in Grant, where: g.public_id == ^ctx.issued.grant_id))
    old = DateTime.add(DateTime.utc_now(), -86_401)

    Repo.update_all(from(c in Client, where: c.public_id == ^ctx.client.client_id),
      set: [inserted_at: old]
    )

    observer = self()

    assert {:ok, {issued, worker, monitor, cleanup}} =
             Repo.transaction(fn ->
               {:ok, issued} =
                 Store.issue_code(
                   ctx.principal,
                   OAuthFixtures.authorization(ctx.client.client_id),
                   OAuthFixtures.resource(),
                   ctx.snapshot
                 )

               worker =
                 start_supervised!(
                   {Task,
                    fn ->
                      :ok = Sandbox.checkout(Repo, sandbox: false)
                      %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
                      send(observer, {:cleanup_started, self(), connection})
                      send(observer, {:cleaned, self(), Store.cleanup(10)})
                      Sandbox.checkin(Repo)
                    end}
                 )

               monitor = Process.monitor(worker)
               assert_receive {:cleanup_started, ^worker, connection}, 5_000

               cleanup =
                 cleanup_started(worker, connection, System.monotonic_time(:millisecond) + 1_500)

               {issued, worker, monitor, cleanup}
             end)

    result =
      case cleanup do
        {:finished, result} ->
          result

        :blocked ->
          assert_receive {:cleaned, ^worker, result}, 5_000
          result
      end

    assert result == {:ok, %{clients: 0, grants: 0}}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000

    assert {:ok, _} =
             Store.exchange(
               OAuthFixtures.exchange(ctx.client.client_id, issued.code),
               OAuthFixtures.resource()
             )
  end

  test "expired-code cleanup preserves a grant consumed by a concurrent exchange", ctx do
    expired = DateTime.add(DateTime.utc_now(), -1)

    Repo.update_all(from(c in Code, where: c.grant_id == ^ctx.issued.grant_id),
      set: [expires_at: expired]
    )

    observer = self()

    # Model an exchange that acquired the grant before code expiry and is
    # committing consumption after expiry. Other connections still see the
    # expired, unconsumed code until this transaction commits.
    assert {:ok, {worker, monitor, cleanup}} =
             Repo.transaction(fn ->
               Repo.one!(
                 from(g in Grant, where: g.public_id == ^ctx.issued.grant_id, lock: "FOR UPDATE")
               )

               Repo.update_all(from(c in Code, where: c.grant_id == ^ctx.issued.grant_id),
                 set: [consumed_at: DateTime.utc_now()]
               )

               worker =
                 start_supervised!(
                   {Task,
                    fn ->
                      :ok = Sandbox.checkout(Repo, sandbox: false)
                      %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
                      send(observer, {:cleanup_started, self(), connection})
                      send(observer, {:cleaned, self(), Store.cleanup(10)})
                      Sandbox.checkin(Repo)
                    end}
                 )

               monitor = Process.monitor(worker)
               assert_receive {:cleanup_started, ^worker, connection}, 5_000

               cleanup =
                 cleanup_started(worker, connection, System.monotonic_time(:millisecond) + 1_500)

               {worker, monitor, cleanup}
             end)

    result =
      case cleanup do
        {:finished, result} ->
          result

        :blocked ->
          assert_receive {:cleaned, ^worker, result}, 5_000
          result
      end

    assert result == {:ok, %{clients: 0, grants: 0}}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000
    assert Repo.get(Grant, ctx.issued.grant_id)
    assert {:ok, %{clients: 0, grants: 0}} = Store.cleanup(10)
  end

  defp cleanup_started(worker, connection, deadline) do
    receive do
      {:cleaned, ^worker, result} -> {:finished, result}
    after
      0 ->
        %{rows: [[blocked]]} =
          Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [connection])

        cond do
          blocked ->
            :blocked

          System.monotonic_time(:millisecond) < deadline ->
            cleanup_started(worker, connection, deadline)

          true ->
            flunk("Cleanup neither finished nor reached its conflicting row lock")
        end
    end
  end

  defp assert_blocked(connection, deadline) do
    %{rows: [[blocked]]} =
      Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [connection])

    cond do
      blocked -> :ok
      System.monotonic_time(:millisecond) < deadline -> assert_blocked(connection, deadline)
      true -> flunk("Operation did not wait for the installation row lock")
    end
  end

  defp race(params) do
    observer = self()

    workers =
      for index <- 1..2 do
        pid =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:ready, self(), connection})

               receive do
                 :exchange ->
                   send(
                     observer,
                     {:result, self(), Store.exchange(params, OAuthFixtures.resource())}
                   )
               after
                 10_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end

               Sandbox.checkin(Repo)
             end},
            id: {:oauth_racer, index}
          )

        {pid, Process.monitor(pid)}
      end

    connections =
      Enum.map(workers, fn {pid, _} ->
        assert_receive {:ready, ^pid, connection}, 5_000
        connection
      end)

    assert length(Enum.uniq(connections)) == 2
    Enum.each(workers, fn {pid, _} -> send(pid, :exchange) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 10_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end
end
