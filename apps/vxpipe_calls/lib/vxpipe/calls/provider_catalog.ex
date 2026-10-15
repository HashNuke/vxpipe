defmodule Vxpipe.Calls.ProviderCatalog do
  @moduledoc "Authorized model listings and public credential availability for one tenant."

  alias Vxpipe.CallEngine.ModelCatalog

  alias Vxpipe.Calls.{
    CallSpecAuthorization,
    EffectiveServiceBindings,
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
    with :ok <- CallSpecAuthorization.authorize(principal, :read, tenant_key),
         {:ok, providers} <- ModelCatalog.providers(capability),
         {:ok, %{bindings: bindings}} <- EffectiveServiceBindings.list(tenant_key, options) do
      visible = visible_bindings(principal, bindings)
      {:ok, %{providers: Enum.map(providers, &availability(&1, visible))}}
    end
  end

  def providers(authority, tenant_key, capability, options) do
    with :ok <- CallSpecAuthorization.authorize(authority, :read, tenant_key),
         {:ok, providers} <- ModelCatalog.providers(capability),
         {:ok, %{bindings: bindings}} <- EffectiveServiceBindings.list(tenant_key, options) do
      {:ok, %{providers: Enum.map(providers, &availability(&1, bindings))}}
    end
  end

  def models(authority, tenant_key, provider, capability, options) do
    with :ok <- CallSpecAuthorization.authorize(authority, :read, tenant_key),
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
end
