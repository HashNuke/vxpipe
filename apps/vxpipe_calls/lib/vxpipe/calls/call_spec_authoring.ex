defmodule Vxpipe.Calls.CallSpecAuthoring do
  @moduledoc "Principal-aware spec writes; platform runtime inheritance is not a tenant authoring grant."
  alias Vxpipe.Calls.{CallSpecs, InstallationOperator, Principal, ProviderAuth}

  def save(authority, tenant_key, source, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options) do
      CallSpecs.save(tenant_key, source, options)
    end
  end

  def publish(authority, tenant_key, id, revision, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options) do
      CallSpecs.publish(tenant_key, id, revision, options)
    end
  end

  defp authorize(%InstallationOperator{grant: :installation_operator}, tenant_key, options) do
    with :ok <- ProviderAuth.tenant_key(tenant_key) do
      {:ok, Keyword.delete(options, :service_authoring_owner)}
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
