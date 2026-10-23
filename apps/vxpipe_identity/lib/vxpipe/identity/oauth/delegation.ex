defmodule Vxpipe.Identity.OAuth.Delegation do
  @moduledoc "Consent snapshots and delegated authority over freshly loaded user records."

  alias Vxpipe.Identity.Principal

  def snapshot(%Principal{} = principal) do
    %{
      authorization_version: principal.authorization_version,
      role_public_id: principal.role_public_id,
      role_revision: principal.role_revision,
      authority: %{
        "grants" => principal.grants |> MapSet.to_list() |> Enum.sort(),
        "account_kind" => Atom.to_string(principal.account_kind),
        "assigned_tenants" =>
          Map.new(principal.assigned_tenants || %{}, fn {key, access} ->
            {key, Atom.to_string(access)}
          end),
        "all_tenant_actions" =>
          (principal.all_tenant_actions || MapSet.new()) |> MapSet.to_list() |> Enum.sort()
      }
    }
  end

  @doc "The store must first check token, grant expiry/revocation and resource binding."
  def principal(user, role, grant) do
    with true <- current?(user, role, grant),
         {:ok, current} <- Principal.for_oauth_grant(user, role, grant.public_id),
         {:ok, approved} <- approved(grant.authority) do
      {:ok,
       %{
         current
         | grants: MapSet.intersection(current.grants, approved.grants),
           delegation: Map.take(approved, [:assigned_tenants, :all_tenant_actions])
       }}
    else
      _invalid -> {:error, :invalid_grant}
    end
  end

  defp current?(user, role, grant) do
    user.public_id == grant.user_public_id and is_nil(user.disabled_at) and
      is_integer(user.authorization_version) and user.authorization_version > 0 and
      user.authorization_version == grant.authorization_version and
      user.role_public_id == role.public_id and role.public_id == grant.role_public_id and
      is_integer(role.revision) and role.revision > 0 and role.revision == grant.role_revision
  end

  defp approved(%{
         "grants" => grants,
         "assigned_tenants" => assigned,
         "all_tenant_actions" => all
       })
       when is_list(grants) and is_map(assigned) and is_list(all) do
    if Enum.all?(grants ++ all, &is_binary/1) and
         Enum.all?(assigned, fn {key, access} ->
           is_binary(key) and access in ["read", "read_write"]
         end) do
      {:ok,
       %{
         grants: MapSet.new(grants),
         assigned_tenants:
           Map.new(assigned, fn {key, access} ->
             {key, if(access == "read", do: :read, else: :read_write)}
           end),
         all_tenant_actions: MapSet.new(all)
       }}
    else
      {:error, :invalid_grant}
    end
  end

  defp approved(_authority), do: {:error, :invalid_grant}
end
