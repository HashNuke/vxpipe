defmodule Vxpipe.Calls.ProviderCatalog do
  @moduledoc "Authorized model listings and public credential availability for one tenant."

  alias Vxpipe.CallEngine.ModelCatalog
  alias Vxpipe.Calls.{EffectiveServiceBindings, InstallationOperator, Principal, ProviderAuth}

  def providers(authority, tenant_key, capability, options) do
    with :ok <- authorize(authority, tenant_key),
         {:ok, providers} <- ModelCatalog.providers(capability),
         {:ok, %{bindings: bindings}} <- EffectiveServiceBindings.list(tenant_key, options) do
      {:ok, %{providers: Enum.map(providers, &availability(&1, bindings))}}
    end
  end

  def models(authority, tenant_key, provider, capability, options) do
    with :ok <- authorize(authority, tenant_key),
         {:ok, models} <- ModelCatalog.models(provider, capability),
         {:ok, _directory} <- EffectiveServiceBindings.list(tenant_key, options) do
      {:ok, %{models: models}}
    end
  end

  defp availability(provider, bindings) do
    required? = provider.id != "morse"

    available? =
      not required? or
        Enum.any?(bindings, &(&1.provider == provider.id and &1.status == :connected))

    Map.merge(provider, %{credential_required: required?, credential_available: available?})
  end

  defp authorize(%InstallationOperator{grant: :installation_operator}, tenant_key),
    do: ProviderAuth.tenant_key(tenant_key)

  defp authorize(%Principal{tenant_key: tenant_key, scopes: scopes}, tenant_key) do
    with :ok <- ProviderAuth.tenant_key(tenant_key) do
      if MapSet.member?(scopes, :admin), do: :ok, else: {:error, :insufficient_scope}
    end
  end

  defp authorize(%Principal{}, _tenant_key), do: {:error, :tenant_access_forbidden}
  defp authorize(_authority, _tenant_key), do: {:error, :authoring_authority_required}
end
