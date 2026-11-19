defmodule Vxpipe.Persistence.DiagnosticsSettingsSessionTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Identity.Principal
  alias Vxpipe.Persistence.{DiagnosticsSettingsStore, Repo}
  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentitySession, IdentityUser}

  test "authority expiring while its session lock is held cannot update diagnostics settings" do
    {actor, user} = Sandbox.unboxed_run(Repo, &actor/0)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(s in IdentitySession, where: s.user_id == ^user.id))
        Repo.delete!(user)
      end)
    end)

    supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})
    parent = self()

    holder =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            session =
              Repo.one!(
                from(s in IdentitySession,
                  where: s.public_id == ^actor.session_public_id,
                  lock: "FOR UPDATE"
                )
              )

            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:session_locked, backend})

            receive do
              :expire_and_release ->
                Repo.update!(Ecto.Changeset.change(session, expires_at: DateTime.utc_now()))
            after
              5_000 -> Repo.rollback(:release_timeout)
            end
          end)
        end)
      end)

    assert_receive {:session_locked, backend}, 1_000

    writer =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            result = DiagnosticsSettingsStore.update(actor, true, 0)
            Repo.rollback({:observed, result})
          end)
        end)
      end)

    try do
      assert wait_for_blocked(backend, System.monotonic_time(:millisecond) + 2_000)
    after
      send(holder.pid, :expire_and_release)
    end

    assert {:ok, _expired} = Task.await(holder, 5_000)
    assert {:error, {:observed, {:error, :forbidden}}} = Task.await(writer, 5_000)
  end

  defp wait_for_blocked(backend, deadline) do
    result =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!(
          "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND $1 = ANY(pg_blocking_pids(pid)))",
          [backend]
        )
      end)

    cond do
      result.rows == [[true]] -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> wait_for_blocked(backend, deadline)
    end
  end

  defp actor do
    role = Repo.get_by!(IdentityRole, kind: "admin")
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

    {struct(Principal,
       account_kind: :admin,
       user_public_id: user.public_id,
       session_public_id: session.public_id
     ), user}
  end
end
