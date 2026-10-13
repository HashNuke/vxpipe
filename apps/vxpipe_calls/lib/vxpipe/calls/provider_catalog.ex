defmodule Vxpipe.Calls.ProviderCatalog do
  @moduledoc "Authorized model listings and public credential availability for one tenant."

  alias Vxpipe.CallEngine.ModelCatalog

  alias Vxpipe.Calls.{
    EffectiveServiceBindings,
    InstallationOperator,
    Principal,
    ProviderAuth,
    UserAuthorization
  }

  alias Vxpipe.Identity.Principal, as: UserPrincipal

  # Safe authoring catalogs for assigned members.
  #
  # Requires exact `call_specs.read` tenant authority (never broad
  # `tenant_services.read`) and never returns credentials, secrets, or
  # management metadata. Availability only reflects tenant-owned bindings
  # unless the author is allowed to reference platform services. Output is
  # limited to public provider/model listings plus boolean availability.
  def providers(%UserPrincipal{} = principal, tenant_key, capability, options)
      when is_binary(tenant_key) and is_list(options) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant(principal, "call_specs.read", tenant_key),
         {:ok, providers} <- ModelCatalog.providers(capability),
         {:ok, %{bindings: bindings}} <- EffectiveServiceBindings.list(tenant_key, options) do
      visible = visible_bindings(principal, bindings)
      {:ok, %{providers: Enum.map(providers, &availability(&1, visible))}}
    end
  end

  def providers(authority, tenant_key, capability, options) do
    with :ok <- authorize(authority, tenant_key),
         {:ok, providers} <- ModelCatalog.providers(capability),
         {:ok, %{bindings: bindings}} <- EffectiveServiceBindings.list(tenant_key, options) do
      {:ok, %{providers: Enum.map(providers, &availability(&1, bindings))}}
    end
  end

  def models(%UserPrincipal{} = principal, tenant_key, provider, capability, options)
      when is_binary(tenant_key) and is_binary(provider) and is_list(options) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant(principal, "call_specs.read", tenant_key),
         {:ok, models} <- ModelCatalog.models(provider, capability),
         {:ok, _directory} <- EffectiveServiceBindings.list(tenant_key, options) do
      {:ok, %{models: models}}
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

  defp visible_bindings(principal, bindings) do
    if UserAuthorization.platform_authoring_allowed?(principal) do
      bindings
    else
      Enum.filter(bindings, &(&1.source == :tenant))
    end
  end

  defp authorize(%InstallationOperator{grant: :installation_operator}, tenant_key),
    do: ProviderAuth.tenant_key(tenant_key)

  defp authorize(%UserPrincipal{} = principal, tenant_key) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant_service_read(principal, tenant_key) do
      :ok
    end
  end

  defp authorize(%Principal{tenant_key: tenant_key, scopes: scopes}, tenant_key) do
    with :ok <- ProviderAuth.tenant_key(tenant_key) do
      if MapSet.member?(scopes, :admin), do: :ok, else: {:error, :insufficient_scope}
    end
  end

  defp authorize(%Principal{}, _tenant_key), do: {:error, :tenant_access_forbidden}
  defp authorize(_authority, _tenant_key), do: {:error, :authoring_authority_required}
end
