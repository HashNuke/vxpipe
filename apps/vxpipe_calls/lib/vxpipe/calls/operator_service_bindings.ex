defmodule Vxpipe.Calls.OperatorServiceBindings do
  @moduledoc "Installation- or user-authorized effective provider inventory."
  alias Vxpipe.Calls.{
    EffectiveServiceBindings,
    InstallationOperator,
    ProviderAuth,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  def list(%UserPrincipal{} = principal, :platform, options) when is_list(options) do
    with :ok <- UserAuthorization.authorize_installation(principal, "platform_services.read"),
         {:ok, directory} <- EffectiveServiceBindings.list(:platform, options) do
      {:ok, Map.put(directory, :model_catalog, Vxpipe.CallEngine.ModelCatalog.catalog())}
    end
  end

  def list(%UserPrincipal{} = principal, {:tenant, tenant_key} = scope, options)
      when is_list(options) do
    list(principal, tenant_key, options) |> wrap_scope(scope)
  end

  def list(%UserPrincipal{} = principal, tenant_key, options)
      when is_binary(tenant_key) and is_list(options) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant_service_read(principal, tenant_key),
         {:ok, directory} <- EffectiveServiceBindings.list(tenant_key, options),
         :ok <- validate_directory_tenant(directory, tenant_key) do
      directory =
        if UserAuthorization.authorize_credential_read(principal, tenant_key) == :ok do
          directory
        else
          Map.update!(directory, :bindings, fn bindings ->
            Enum.map(bindings, &Map.merge(&1, %{credential_id: nil, saved_fields: []}))
          end)
        end

      {:ok, Map.put(directory, :model_catalog, Vxpipe.CallEngine.ModelCatalog.catalog())}
    else
      {:error, :invalid_tenant_key} = error -> error
      error -> error
    end
  end

  def list(%InstallationOperator{grant: :installation_operator}, scope, options) do
    with {:ok, directory} <- EffectiveServiceBindings.list(scope, options) do
      {:ok, Map.put(directory, :model_catalog, Vxpipe.CallEngine.ModelCatalog.catalog())}
    end
  end

  def list(_authority, _scope, _options), do: {:error, :installation_operator_required}

  defp wrap_scope({:ok, directory}, _scope), do: {:ok, directory}
  defp wrap_scope(error, _scope), do: error

  defp validate_directory_tenant(%{tenant: %{key: key}}, key), do: :ok

  defp validate_directory_tenant(%{tenant: nil}, _key),
    do: {:error, :service_directory_unavailable}

  defp validate_directory_tenant(_directory, _key), do: {:error, :service_directory_unavailable}
end
