defmodule Vxpipe.Persistence.OAuth.Retention do
  @moduledoc "Bounded removal of expired/revoked grants and unused client registrations."
  import Ecto.Query
  alias Vxpipe.Persistence.OAuth.{Client, Grant, Transaction}
  alias Vxpipe.Persistence.Repo

  def cleanup(limit) when is_integer(limit) and limit in 1..1_000,
    do: Transaction.run(fn -> {:ok, sweep(limit)} end)

  def cleanup(_), do: {:error, :invalid_limit}

  def expire_user_grants(user_id) do
    grants = from(g in expired_grants(100), where: g.user_id == ^user_id)
    _ = delete_grants(grants)
    :ok
  end

  def sweep(limit) do
    now = Transaction.now()
    old = DateTime.add(now, -86_400)

    {grant_count, _} = delete_grants(expired_grants(limit))

    clients =
      from(c in Client,
        where:
          c.inserted_at <= ^old and
            fragment(
              "NOT EXISTS (SELECT 1 FROM oauth_grants g WHERE g.client_id = ?)",
              c.public_id
            ),
        order_by: [asc: c.inserted_at, asc: c.public_id],
        limit: ^limit,
        lock: "FOR UPDATE SKIP LOCKED",
        select: c.public_id
      )

    # Issuance holds a client KEY SHARE lock before writing its grant. Skip
    # those rows instead of reversing issuance's client/grant lock order.
    # Recheck absence in a new statement after locking: a grant may have
    # committed between the candidate snapshot and acquisition of its lock.
    client_ids = Repo.all(clients, Transaction.options())

    {client_count, _} =
      Repo.delete_all(
        from(c in Client,
          where:
            c.public_id in ^client_ids and
              fragment(
                "NOT EXISTS (SELECT 1 FROM oauth_grants g WHERE g.client_id = ?)",
                c.public_id
              )
        ),
        Transaction.options()
      )

    %{grants: grant_count, clients: client_count}
  end

  defp expired_grants(limit) do
    from(g in expired_grant_query(),
      order_by: [asc: g.inserted_at, asc: g.public_id],
      limit: ^limit,
      select: g.public_id
    )
  end

  defp expired_grant_query do
    now = Transaction.now()

    from(g in Grant,
      where:
        g.expires_at <= ^now or not is_nil(g.revoked_at) or
          fragment(
            "EXISTS (SELECT 1 FROM oauth_codes c WHERE c.grant_id = ? AND c.consumed_at IS NULL AND c.expires_at <= ?)",
            g.public_id,
            ^now
          )
    )
  end

  defp delete_grants(query) do
    # Exchanges hold the grant lock while consuming a code. Do not wait on a
    # candidate whose expired-code predicate can become stale while blocked.
    ids = Repo.all(lock(query, "FOR UPDATE SKIP LOCKED"), Transaction.options())

    Repo.delete_all(
      from(g in expired_grant_query(), where: g.public_id in ^ids),
      Transaction.options()
    )
  end
end
