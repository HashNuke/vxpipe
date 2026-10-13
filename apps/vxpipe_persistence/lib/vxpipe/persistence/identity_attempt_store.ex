defmodule Vxpipe.Persistence.IdentityAttemptStore do
  @moduledoc "Database-backed cluster-wide login/setup attempt accounting with pruning."

  @behaviour Vxpipe.Identity.Ports.Attempts

  import Ecto.Query

  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.Schema.AuthenticationAttempt

  @impl true
  def record(account, address, now) do
    changeset =
      AuthenticationAttempt.changeset(%AuthenticationAttempt{}, %{
        normalized_account: account,
        client_address: address,
        attempted_at: now
      })

    case Repo.insert(changeset) do
      {:ok, _} ->
        cutoff = DateTime.add(now, -3600, :second)
        _ = Repo.delete_all(from(a in AuthenticationAttempt, where: a.attempted_at < ^cutoff))
        :ok

      {:error, _} ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def recent(account, address, now, window_seconds) do
    cutoff = DateTime.add(now, -window_seconds, :second)

    account_times =
      Repo.all(
        from(a in AuthenticationAttempt,
          where: a.normalized_account == ^account and a.attempted_at > ^cutoff,
          select: a.attempted_at
        )
      )

    address_times =
      Repo.all(
        from(a in AuthenticationAttempt,
          where: a.client_address == ^address and a.attempted_at > ^cutoff,
          select: a.attempted_at
        )
      )

    {:ok, %{account: account_times, address: address_times}}
  rescue
    _ -> {:error, :unavailable}
  end
end
