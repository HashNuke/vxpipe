defmodule Vxpipe.Calls.CallSpecAuthoring do
  @moduledoc "Principal-aware spec writes; platform runtime inheritance is not a tenant authoring grant."
  alias Vxpipe.Calls.{CallSpecs, InstallationOperator, Principal, ProviderAuth, UserAuthorization}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  def save(authority, tenant_key, source, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options),
         :ok <- existing_target(tenant_key, options) do
      CallSpecs.save(tenant_key, source, options)
    end
  end

  def publish(authority, tenant_key, id, revision, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options) do
      CallSpecs.publish(tenant_key, id, revision, options)
    end
  end

  # A supplied ID is only a locator for an existing tenant-owned spec. Creation
  # leaves it unset so CallSpecs allocates the public UUID internally.
  defp existing_target(tenant_key, options) do
    case Keyword.fetch(options, :call_spec_id) do
      :error ->
        :ok

      {:ok, id} ->
        with {:ok, _revision} <- CallSpecs.fetch(tenant_key, id, 1, options), do: :ok
    end
  end

  defp authorize(%InstallationOperator{grant: :installation_operator}, tenant_key, options) do
    with :ok <- ProviderAuth.tenant_key(tenant_key) do
      {:ok, Keyword.delete(options, :service_authoring_owner)}
    end
  end

  defp authorize(%UserPrincipal{} = principal, tenant_key, options) when is_binary(tenant_key) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant(principal, "call_specs.write", tenant_key) do
      if UserAuthorization.platform_authoring_allowed?(principal) do
        {:ok, Keyword.delete(options, :service_authoring_owner)}
      else
        {:ok, Keyword.put(options, :service_authoring_owner, {:tenant, tenant_key})}
      end
    end
  end

  defp authorize(%Principal{tenant_key: tenant_key, scopes: scopes}, tenant_key, options) do
    if MapSet.member?(scopes, :admin),
      do: {:ok, Keyword.put(options, :service_authoring_owner, {:tenant, tenant_key})},
      else: {:error, :insufficient_scope}
  end

  defp authorize(%Principal{}, _tenant_key, _options), do: {:error, :tenant_access_forbidden}
  defp authorize(_authority, _tenant_key, _options), do: {:error, :authoring_authority_required}
end
