defmodule Vxpipe.Persistence.Integration.OAuthBrowserTransactionTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Persistence.{OAuthFixtures, Repo}

  alias Vxpipe.Persistence.OAuth.{
    AuthorizationRequest,
    Browser,
    Client,
    Grant,
    Store,
    Transaction
  }

  alias Vxpipe.Persistence.Schema.{AuthenticationInstallation, IdentityUser}

  @moduletag :integration

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    installation = Repo.get!(AuthenticationInstallation, "default")
    %{user: user, principal: principal} = OAuthFixtures.browser_user()
    {:ok, client} = Store.register_client(OAuthFixtures.registration())
    binding = Transaction.random()

    {:ok, id} =
      Browser.begin_authorization(
        OAuthFixtures.authorization(client.client_id),
        OAuthFixtures.resource(),
        binding
      )

    {:ok, _} = Browser.consent(id, binding, principal)

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

    %{client: client, principal: principal, id: id, binding: binding}
  end

  test "concurrent approval and denial consume the browser transaction only once", ctx do
    results = complete_concurrently(ctx)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :invalid_request}, &1)) == 1
    {:ok, response} = Enum.find(results, &match?({:ok, _}, &1))
    assert response.state == "test-state"
    assert response.redirect_uri == "http://127.0.0.1:43210/callback"

    grants = Repo.all(from(g in Grant, where: g.client_id == ^ctx.client.client_id))

    assert Repo.aggregate(
             from(r in AuthorizationRequest, where: r.client_id == ^ctx.client.client_id),
             :count
           ) == 0

    case response do
      %{code: code, grant_id: grant_id} ->
        assert [%Grant{public_id: ^grant_id}] = grants

        assert {:ok, _} =
                 Store.exchange(
                   OAuthFixtures.exchange(ctx.client.client_id, code),
                   OAuthFixtures.resource()
                 )

      %{error: "access_denied"} ->
        assert grants == []
    end
  end

  defp complete_concurrently(ctx) do
    observer = self()

    workers =
      Enum.map([:approve, :deny], fn decision ->
        pid =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:ready, self(), connection})

               receive do
                 :complete ->
                   result =
                     Browser.complete_authorization(ctx.id, ctx.binding, ctx.principal, decision)

                   send(observer, {:result, self(), result})
               after
                 5_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end

               Sandbox.checkin(Repo)
             end},
            id: {:consent_racer, decision}
          )

        {pid, Process.monitor(pid)}
      end)

    connections =
      Enum.map(workers, fn {pid, _} ->
        assert_receive {:ready, ^pid, connection}, 5_000
        connection
      end)

    assert length(Enum.uniq(connections)) == 2
    Enum.each(workers, fn {pid, _} -> send(pid, :complete) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end
end
