defmodule Vxpipe.Calls.CallSpecAuthorization do
  @moduledoc "Shared read/write policy for call specs and their authoring catalogs."

  alias Vxpipe.Calls.{InstallationOperator, Principal, ProviderAuth, UserAuthorization}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  @doc "Checks tool discovery; selected resources still require their own tenant authorization."
  def authorize(%Principal{tenant_key: tenant} = principal, action),
    do: authorize(principal, action, tenant)

  def authorize(%UserPrincipal{} = principal, action) when action in [:read, :write] do
    UserAuthorization.authorize_any_tenant(principal, permission(action))
  end

  def authorize(
        %InstallationOperator{grant: :installation_operator, credential_kind: :platform_api_key},
        action
      )
      when action in [:read, :write], do: :ok

  def authorize(_authority, _action), do: {:error, :authoring_authority_required}

  @doc "Checks one tenant, preserving browser grants and trusted installation domain callers."
  def authorize(authority, action, tenant) when action in [:read, :write] do
    with :ok <- ProviderAuth.tenant_key(tenant), do: tenant_authority(authority, action, tenant)
  end

  def authorize(_authority, _action, _tenant), do: {:error, :authoring_authority_required}

  defp tenant_authority(%InstallationOperator{grant: :installation_operator}, _action, _tenant),
    do: :ok

  defp tenant_authority(%UserPrincipal{} = principal, action, tenant) do
    UserAuthorization.authorize_tenant(principal, permission(action), tenant)
  end

  defp tenant_authority(
         %Principal{tenant_key: tenant, scopes: %MapSet{} = scopes},
         _action,
         tenant
       ) do
    if MapSet.member?(scopes, :admin), do: :ok, else: {:error, :insufficient_scope}
  end

  defp tenant_authority(%Principal{}, _action, _tenant), do: {:error, :tenant_access_forbidden}
  defp tenant_authority(_authority, _action, _tenant), do: {:error, :authoring_authority_required}

  defp permission(:read), do: "call_specs.read"
  defp permission(:write), do: "call_specs.write"
end
