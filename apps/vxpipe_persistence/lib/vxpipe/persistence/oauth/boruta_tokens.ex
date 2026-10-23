defmodule Vxpipe.Persistence.OAuth.BorutaTokens do
  @moduledoc false
  @behaviour Boruta.Oauth.AccessTokens
  import Ecto.Query
  alias Vxpipe.Persistence.OAuth.{BorutaClients, BorutaContext, Grant, Token, Transaction}
  alias Vxpipe.Persistence.Repo

  @impl true
  def get_by(value: raw), do: lookup(:access_digest, raw)
  def get_by(refresh_token: raw), do: lookup(:refresh_digest, raw)

  defp lookup(field, raw) do
    case BorutaContext.current() do
      %{grant: grant} = context ->
        digest = Transaction.digest(raw)

        row =
          Repo.one(
            from(t in Token,
              where: field(t, ^field) == ^digest and t.grant_id == ^grant.public_id
            ),
            Transaction.options()
          )

        if row, do: project(row, context), else: nil

      _ ->
        nil
    end
  end

  @impl true
  def create(_params, refresh_token: true) do
    %{grant: grant} = context = BorutaContext.current()
    access = Transaction.random()
    refresh = Transaction.random()
    expires = DateTime.add(Transaction.now(), 600)

    expires =
      if DateTime.compare(expires, grant.expires_at) == :gt, do: grant.expires_at, else: expires

    row =
      Repo.insert!(
        %Token{
          grant_id: grant.public_id,
          access_digest: Transaction.digest(access),
          refresh_digest: Transaction.digest(refresh),
          access_expires_at: expires
        },
        Transaction.options()
      )

    {:ok, %{project(row, context) | value: access, refresh_token: refresh}}
  end

  @impl true
  def revoke_refresh_token(token) do
    %{grant: grant} = BorutaContext.current()

    {1, _} =
      Repo.update_all(
        from(t in Token,
          where:
            t.public_id == ^token.value and t.grant_id == ^grant.public_id and
              is_nil(t.refresh_consumed_at)
        ),
        [set: [refresh_consumed_at: Transaction.now()]],
        Transaction.options()
      )

    {:ok, token}
  end

  @impl true
  def revoke(token) do
    %{grant: grant} = BorutaContext.current()

    Repo.update_all(
      from(g in Grant, where: g.public_id == ^grant.public_id),
      [set: [revoked_at: Transaction.now()]],
      Transaction.options()
    )

    {:ok, token}
  end

  defp project(row, %{grant: grant, user: user}) do
    %Boruta.Oauth.Token{
      type: "access_token",
      value: row.public_id,
      client: BorutaClients.get_client(grant.client_id),
      sub: user.public_id,
      scope: "mcp",
      expires_at: DateTime.to_unix(row.access_expires_at),
      inserted_at: grant.inserted_at,
      revoked_at: grant.revoked_at,
      refresh_token_revoked_at: row.refresh_consumed_at
    }
  end
end
