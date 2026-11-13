defmodule Vxpipe.Calls.VoiceCatalog do
  @moduledoc "Tenant-authorized voice discovery using the call spec's effective credential binding."
  alias Vxpipe.CallEngine.VoiceCatalog, as: Catalog

  alias Vxpipe.Calls.{
    CallSpecAuthorization,
    CallSpecCredentials,
    EffectiveServiceBindings,
    Principal,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  def request(authority, tenant, scope, operation, query, options \\ []) do
    with :ok <- CallSpecAuthorization.authorize(authority, :read, tenant),
         {:ok, descriptor} <- Catalog.describe(scope),
         {:ok, payload} <- credential(authority, tenant, scope, options) do
      perform(operation, scope, query, descriptor, payload, options)
    end
  rescue
    _ -> {:error, :voice_catalog_unavailable}
  catch
    _, _ -> {:error, :voice_catalog_unavailable}
  end

  defp credential(_authority, tenant, %{provider: "morse"}, options) do
    with {:ok, _} <- EffectiveServiceBindings.list(tenant, options), do: {:ok, %{}}
  end

  defp credential(authority, tenant, scope, options) do
    options =
      if tenant_only?(authority),
        do: Keyword.put(options, :service_authoring_owner, {:tenant, tenant}),
        else: Keyword.delete(options, :service_authoring_owner)

    selection = Map.put_new(scope, :credential_name, "default")

    with {:ok, resolved} <- CallSpecCredentials.resolve(tenant, selection, options),
         do: {:ok, resolved.payload}
  end

  defp tenant_only?(%Principal{}), do: true

  defp tenant_only?(%UserPrincipal{} = principal),
    do: not UserAuthorization.platform_authoring_allowed?(principal)

  defp tenant_only?(_), do: false

  defp perform(:describe, _, _, descriptor, _, _), do: {:ok, descriptor}

  defp perform(:list, scope, query, _, payload, options),
    do: Catalog.list(scope, query, payload, options)

  defp perform({:get, id}, scope, _, _, payload, options),
    do: Catalog.get(scope, id, payload, options)

  defp perform(_, _, _, _, _, _), do: {:error, :invalid_voice_query}
end
