defmodule Vxpipe.Identity.AccountAuthority do
  @moduledoc "Account-only machine permissions and trusted write attribution."
  alias Vxpipe.Identity.{ApiKeyActor, Authorization}

  @machine_permissions ~w(users.read users.members.write users.admins.write users.superadmins.write)
  @actor_fields [:actor_user_public_id, :actor_session_public_id, :actor_api_key_public_id]
  @reserved @actor_fields ++
              Enum.map(@actor_fields, &Atom.to_string/1) ++
              [:audit, :audit_event, "audit", "audit_event"]

  def require_identity(%ApiKeyActor{api_key_id: id}) do
    if ApiKeyActor.valid_id?(id), do: :ok, else: {:error, :forbidden}
  end

  def require_identity(actor), do: Authorization.require_actor_identity(actor)

  def require_read(actor) do
    if MapSet.member?(grants(actor), "users.read"), do: :ok, else: {:error, :forbidden}
  end

  def grants(%ApiKeyActor{} = actor) do
    if require_identity(actor) == :ok, do: MapSet.new(@machine_permissions), else: MapSet.new()
  end

  def grants(%{grants: %MapSet{} = grants}), do: grants
  def grants(_actor), do: MapSet.new()

  def machine_permission?(permission), do: permission in @machine_permissions

  def require_update_fields(%ApiKeyActor{}, changes) do
    forbidden = ~w(password password_confirmation password_hash expected_current_password_hash)a

    if Enum.any?(
         forbidden,
         &(Map.has_key?(changes, &1) or Map.has_key?(changes, Atom.to_string(&1)))
       ), do: {:error, :forbidden}, else: :ok
  end

  def require_update_fields(_browser, _changes), do: :ok

  def attribution(%ApiKeyActor{api_key_id: id}), do: %{actor_api_key_public_id: id}

  def attribution(actor),
    do: %{
      actor_user_public_id: actor.user_public_id,
      actor_session_public_id: actor.session_public_id
    }

  def stamp(attrs, attribution), do: attrs |> Map.drop(@reserved) |> Map.merge(attribution)
end
