defmodule Vxpipe.Persistence.OAuth.AccountActor do
  @moduledoc "Revalidates delegated account mutations inside the caller's transaction."

  alias Vxpipe.Identity.{AccountAuthority, ApiKeyActor}
  alias Vxpipe.Identity.OAuth.Delegation
  alias Vxpipe.Persistence.OAuth.{Authority, Grant, Transaction}
  alias Vxpipe.Persistence.Repo

  def revalidate(attrs, permissions) do
    grant_id = value(attrs, :actor_oauth_grant_public_id)
    user_id = value(attrs, :actor_user_public_id)

    with true <- Repo.in_transaction?(),
         true <- ApiKeyActor.valid_id?(grant_id) and ApiKeyActor.valid_id?(user_id),
         true <-
           is_nil(value(attrs, :actor_session_public_id)) and
             is_nil(value(attrs, :actor_api_key_public_id)),
         true <-
           is_list(permissions) and permissions != [] and
             Enum.all?(permissions, &AccountAuthority.machine_permission?/1),
         %Grant{} = stored <- Repo.get(Grant, grant_id, Transaction.options()),
         {:ok, context} <- Authority.grant(grant_id, stored.resource),
         true <- context.user.public_id == user_id,
         grant = Map.put(Authority.project_grant(context.grant), :user_public_id, user_id),
         {:ok, principal} <- Delegation.principal(context.user, context.role, grant),
         true <- Enum.all?(permissions, &MapSet.member?(principal.grants, &1)) do
      :ok
    else
      _denied -> {:error, :forbidden}
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
