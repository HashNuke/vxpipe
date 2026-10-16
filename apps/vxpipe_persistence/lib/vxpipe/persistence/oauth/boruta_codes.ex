defmodule Vxpipe.Persistence.OAuth.BorutaCodes do
  @moduledoc false
  @behaviour Boruta.Oauth.Codes
  import Ecto.Query

  alias Vxpipe.Persistence.OAuth.{
    BorutaClients,
    BorutaContext,
    BorutaResourceOwners,
    Code,
    Transaction
  }

  alias Vxpipe.Persistence.Repo

  @impl true
  def get_by(value: raw, redirect_uri: redirect) do
    case BorutaContext.current() do
      %{grant: grant} = context ->
        digest = Transaction.digest(raw)

        row =
          Repo.one(
            from(c in Code,
              where:
                c.digest == ^digest and c.redirect_uri == ^redirect and
                  c.grant_id == ^grant.public_id
            ),
            Transaction.options()
          )

        if row, do: project(row, context), else: nil

      _ ->
        nil
    end
  end

  @impl true
  def create(params) do
    %{grant: grant} = context = BorutaContext.current()
    raw = Transaction.random()

    row =
      Repo.insert!(
        %Code{
          grant_id: grant.public_id,
          digest: Transaction.digest(raw),
          redirect_uri: params.redirect_uri,
          challenge_hash: Boruta.Oauth.Token.hash(params.code_challenge),
          expires_at: DateTime.add(Transaction.now(), 60)
        },
        Transaction.options()
      )

    {:ok, %{project(row, context) | value: raw, state: params.state}}
  end

  @impl true
  def revoke(token) do
    %{grant: grant} = BorutaContext.current()

    {1, _} =
      Repo.update_all(
        from(c in Code,
          where:
            c.public_id == ^token.value and c.grant_id == ^grant.public_id and
              is_nil(c.consumed_at)
        ),
        [set: [consumed_at: Transaction.now()]],
        Transaction.options()
      )

    {:ok, token}
  end

  @impl true
  def revoke_previous_token(token), do: {:ok, token}

  defp project(row, %{grant: grant, user: user}) do
    %Boruta.Oauth.Token{
      type: "code",
      value: row.public_id,
      client: BorutaClients.get_client(grant.client_id),
      resource_owner: BorutaResourceOwners.owner(user.public_id, grant.public_id),
      sub: user.public_id,
      scope: "mcp",
      redirect_uri: row.redirect_uri,
      code_challenge_hash: row.challenge_hash,
      code_challenge_method: "S256",
      expires_at: DateTime.to_unix(row.expires_at),
      revoked_at: row.consumed_at
    }
  end
end
