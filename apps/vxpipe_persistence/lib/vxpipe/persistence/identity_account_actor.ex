defmodule Vxpipe.Persistence.IdentityAccountActor do
  @moduledoc "Transaction-time account actor checks; browser checks remain in IdentityRecord."
  import Ecto.Query
  alias Vxpipe.Identity.{AccountAuthority, ApiKeyActor}
  alias Vxpipe.Persistence.{IdentityRecord, Repo}
  alias Vxpipe.Persistence.Schema.ApiKey
  @private [log: false, telemetry_event: nil]

  def revalidate(attrs, permissions, operation) do
    cond do
      oauth?(attrs) ->
        Vxpipe.Persistence.OAuth.AccountActor.revalidate(attrs, permissions)

      machine?(attrs) ->
        with {:ok, actor} <- ApiKeyActor.new(value(attrs, :actor_api_key_public_id)),
             true <-
               Enum.all?(
                 [:actor_user_public_id, :actor_session_public_id],
                 &is_nil(value(attrs, &1))
               ),
             true <-
               is_list(permissions) and permissions != [] and
                 Enum.all?(permissions, &AccountAuthority.machine_permission?/1),
             :ok <- update_fields(actor, attrs, operation),
             id when is_binary(id) <- lock_platform_key(actor.api_key_id) do
          :ok
        else
          _ -> {:error, :forbidden}
        end

      true ->
        IdentityRecord.revalidate_actor(attrs, permissions)
    end
  end

  def insert_audit(attrs) do
    event = value(attrs, :audit_event)

    cond do
      (machine?(attrs) or oauth?(attrs)) and not is_map(event) ->
        {:error, :unavailable}

      is_map(event) ->
        attribution =
          cond do
            oauth?(attrs) ->
              %{
                actor_user_public_id: value(attrs, :actor_user_public_id),
                actor_oauth_grant_public_id: value(attrs, :actor_oauth_grant_public_id)
              }

            machine?(attrs) ->
              %{actor_api_key_public_id: value(attrs, :actor_api_key_public_id)}

            true ->
              %{actor_user_public_id: value(attrs, :actor_user_public_id)}
          end

        event |> AccountAuthority.stamp(attribution) |> IdentityRecord.insert_audit()

      true ->
        IdentityRecord.insert_audit(event)
    end
  end

  defp lock_platform_key(id) do
    Repo.one(
      from(k in ApiKey,
        where:
          k.public_id == ^id and is_nil(k.tenant_id) and k.scopes == ^["platform"] and
            is_nil(k.revoked_at),
        select: k.public_id,
        lock: "FOR UPDATE"
      ),
      @private
    )
  end

  defp update_fields(actor, attrs, :update),
    do: AccountAuthority.require_update_fields(actor, attrs)

  defp update_fields(_actor, _attrs, :create), do: :ok

  defp machine?(attrs),
    do:
      Map.has_key?(attrs, :actor_api_key_public_id) or
        Map.has_key?(attrs, "actor_api_key_public_id")

  defp oauth?(attrs),
    do:
      Map.has_key?(attrs, :actor_oauth_grant_public_id) or
        Map.has_key?(attrs, "actor_oauth_grant_public_id")

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
