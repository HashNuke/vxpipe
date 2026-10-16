defmodule Vxpipe.Calls.CallSpecAuthoring do
  @moduledoc "Principal-aware spec writes; platform runtime inheritance is not a tenant authoring grant."
  alias Vxpipe.Calls.{CallSpecAuthorization, CallSpecs, Principal, UserAuthorization}
  alias Vxpipe.Identity.Principal, as: UserPrincipal

  def save(authority, tenant_key, source, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options),
         :ok <- existing_target(tenant_key, options) do
      CallSpecs.save(tenant_key, source, options)
    end
  end

  def validate(authority, tenant_key, source, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options) do
      CallSpecs.validate(tenant_key, source, options)
    end
  end

  def publish(authority, tenant_key, id, revision, options) do
    with {:ok, options} <- authorize(authority, tenant_key, options) do
      CallSpecs.publish(tenant_key, id, revision, options)
    end
  end

  # A supplied ID is only a locator for an existing tenant-owned spec. Creation
  # leaves it unset so CallSpecs allocates the database primary key internally.
  defp existing_target(tenant_key, options) do
    case Keyword.fetch(options, :call_spec_id) do
      :error ->
        :ok

      {:ok, id} ->
        with {:ok, _revision} <- CallSpecs.fetch(tenant_key, id, 1, options), do: :ok
    end
  end

  defp authorize(authority, tenant_key, options) do
    with :ok <- CallSpecAuthorization.authorize(authority, :write, tenant_key) do
      if tenant_services_only?(authority),
        do: {:ok, Keyword.put(options, :service_authoring_owner, {:tenant, tenant_key})},
        else: {:ok, Keyword.delete(options, :service_authoring_owner)}
    end
  end

  defp tenant_services_only?(%Principal{}), do: true

  defp tenant_services_only?(%UserPrincipal{} = principal),
    do: not UserAuthorization.platform_authoring_allowed?(principal)

  defp tenant_services_only?(_installation), do: false
end
