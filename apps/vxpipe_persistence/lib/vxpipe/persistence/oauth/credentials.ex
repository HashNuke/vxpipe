defmodule Vxpipe.Persistence.OAuth.Credentials do
  @moduledoc "Digest-only credential lookup and locked exchange preparation."
  import Ecto.Query
  alias Vxpipe.Persistence.OAuth.{Authority, Code, Token, Transaction}
  alias Vxpipe.Persistence.Repo

  def prepare(%{"grant_type" => "authorization_code"} = params, resource) do
    with %Code{} = hint <- lookup(Code, :digest, params["code"]),
         {:ok, context} <- Authority.grant(hint.grant_id, resource),
         true <- context.grant.client_id == params["client_id"],
         %Code{} = code <-
           Repo.one(
             from(c in Code, where: c.public_id == ^hint.public_id, lock: "FOR UPDATE"),
             Transaction.options()
           ),
         true <-
           code.redirect_uri == params["redirect_uri"] and is_nil(code.consumed_at) and
             Transaction.future?(code.expires_at) do
      {:ok, context}
    else
      _ -> {:error, :invalid_grant}
    end
  end

  def prepare(%{"grant_type" => "refresh_token"} = params, resource) do
    with %Token{} = hint <- lookup(Token, :refresh_digest, params["refresh_token"]),
         {:ok, context} <- Authority.grant(hint.grant_id, resource),
         true <- context.grant.client_id == params["client_id"],
         %Token{} = token <-
           Repo.one(
             from(t in Token, where: t.public_id == ^hint.public_id, lock: "FOR UPDATE"),
             Transaction.options()
           ) do
      if is_nil(token.refresh_consumed_at) do
        {:ok, context}
      else
        Authority.revoke(context.grant)
        {:commit_error, :invalid_grant}
      end
    else
      _ -> {:error, :invalid_grant}
    end
  end

  def access(raw, resource) do
    with %Token{} = token <- lookup(Token, :access_digest, raw),
         {:ok, context} <- Authority.grant(token.grant_id, resource),
         true <- Transaction.future?(token.access_expires_at) do
      grant =
        context.grant
        |> Authority.project_grant()
        |> Map.put(:user_public_id, context.user.public_id)

      {:ok, %{context | grant: grant}}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def revoke(params, resource) do
    token =
      lookup(Token, :access_digest, params["token"]) ||
        lookup(Token, :refresh_digest, params["token"])

    with %Token{} <- token,
         {:ok, context} <- Authority.grant(token.grant_id, resource),
         true <- context.grant.client_id == params["client_id"] do
      Authority.revoke(context.grant)
      :ok
    else
      _ -> :ok
    end
  end

  defp lookup(schema, field, raw) do
    digest = Transaction.digest(raw)
    Repo.one(from(row in schema, where: field(row, ^field) == ^digest), Transaction.options())
  end
end
