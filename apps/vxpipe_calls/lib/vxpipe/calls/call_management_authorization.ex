defmodule Vxpipe.Calls.CallManagementAuthorization do
  @moduledoc "Shared authority for creating calls and issuing participant join tokens."

  alias Vxpipe.Calls.{InstallationOperator, Principal, ProviderAuth, UserAuthorization}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  def authorize(%Principal{tenant_key: tenant} = actor), do: authorize(actor, tenant)

  def authorize(%InstallationOperator{
        grant: :installation_operator,
        credential_kind: :platform_api_key
      }),
      do: :ok

  def authorize(_actor), do: {:error, :not_authorized}

  def authorize(actor, tenant) do
    with :ok <- ProviderAuth.tenant_key(tenant), do: tenant_authority(actor, tenant)
  end

  defp tenant_authority(%Principal{tenant_key: tenant, scopes: %MapSet{} = scopes}, tenant) do
    if MapSet.member?(scopes, :calls), do: :ok, else: {:error, :not_authorized}
  end

  defp tenant_authority(%Principal{}, _tenant), do: {:error, :tenant_access_forbidden}

  defp tenant_authority(
         %InstallationOperator{grant: :installation_operator, credential_kind: :platform_api_key},
         _tenant
       ),
       do: :ok

  defp tenant_authority(%UserPrincipal{} = actor, tenant),
    do: UserAuthorization.authorize_tenant(actor, "calls.write", tenant)

  defp tenant_authority(_actor, _tenant), do: {:error, :not_authorized}
end
