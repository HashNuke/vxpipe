defmodule Vxpipe.Calls.UserAuthorization do
  @moduledoc """
  Database-neutral user-principal authorization for browser workflows.

  Wraps `Vxpipe.Identity.Authorization` with the explicit `Vxpipe.Identity.Principal`
  carried on each request. Unknown actions deny. Callers still resolve and check
  the resource's actual tenant at the owning boundary.
  """

  alias Vxpipe.Identity.Authorization

  @tenant_actions [
    "calls.read", "calls.write", "call_specs.read", "call_specs.write",
    "tenant_services.read", "tenant_services.write",
    "tenant_api_keys.write"
  ]

  @spec authorize_tenant(map(), String.t(), String.t()) :: :ok | {:error, :forbidden | term()}
  def authorize_tenant(principal, action, tenant_key)
      when is_map(principal) and is_binary(action) and is_binary(tenant_key) do
    with :ok <- tenant_key_format(tenant_key) do
      principal
      |> context()
      |> then(&Authorization.authorize(principal.grants, action, {:tenant, tenant_key}, &1))
      |> map_denial()
    end
  end

  @spec authorize_installation(map(), String.t()) :: :ok | {:error, :forbidden | term()}
  def authorize_installation(principal, action) when is_map(principal) and is_binary(action) do
    principal
    |> context()
    |> then(&Authorization.authorize(principal.grants, action, :installation, &1))
    |> map_denial()
  end

  @spec context(map()) :: map()
  def context(principal) when is_map(principal) do
    %{
      assigned_tenants: Map.get(principal, :assigned_tenants) || %{},
      all_tenant_actions: Map.get(principal, :all_tenant_actions) || MapSet.new()
    }
  end

  @spec visible_tenant_scope(map()) :: :all | {:assigned, [String.t()]}
  def visible_tenant_scope(principal) when is_map(principal) do
    cond do
      Map.get(principal, :account_kind) in [:superadmin, :admin] ->
        :all

      authorize_installation(principal, "tenants.write") == :ok ->
        :all

      has_all_tenant_grant?(principal) ->
        :all

      true ->
        case listable_assigned_keys(principal) do
          {:ok, visible} -> {:assigned, visible}
          {:error, :forbidden} -> {:assigned, []}
        end
    end
  end

  @spec platform_authoring_allowed?(map()) :: boolean()
  def platform_authoring_allowed?(principal) when is_map(principal) do
    case authorize_installation(principal, "call_specs.use_platform_services") do
      :ok -> true
      _ -> false
    end
  end

  @spec credential_read_action(:platform | term()) :: String.t()
  def credential_read_action(:platform), do: "platform_services.read"
  def credential_read_action(_owner), do: "tenant_services.read"

  @spec credential_write_action(:platform | term()) :: String.t()
  def credential_write_action(:platform), do: "platform_services.write"
  def credential_write_action(_owner), do: "tenant_api_keys.write"

  @spec authorize_tenant_service_read(map(), String.t()) :: :ok | {:error, term()}
  def authorize_tenant_service_read(principal, tenant_key)
      when is_map(principal) and is_binary(tenant_key) do
    authorize_tenant_scoped(principal, "tenant_services.read", tenant_key, false)
  end

  @spec authorize_tenant_service_write(map(), String.t()) :: :ok | {:error, term()}
  def authorize_tenant_service_write(principal, tenant_key)
      when is_map(principal) and is_binary(tenant_key) do
    authorize_tenant_scoped(principal, "tenant_services.write", tenant_key, true)
  end

  @spec authorize_credential_read(map(), term()) :: :ok | {:error, term()}
  def authorize_credential_read(principal, :platform) when is_map(principal),
    do: authorize_installation(principal, "platform_services.read")

  def authorize_credential_read(principal, {:tenant, key})
      when is_map(principal) and is_binary(key) do
    authorize_tenant_scoped(principal, "tenant_services.read", key, false)
  end

  def authorize_credential_read(principal, key) when is_map(principal) and is_binary(key) do
    authorize_tenant_scoped(principal, "tenant_services.read", key, false)
  end

  def authorize_credential_read(_principal, _owner), do: {:error, :forbidden}

  @spec authorize_credential_write(map(), term()) :: :ok | {:error, term()}
  def authorize_credential_write(principal, :platform) when is_map(principal),
    do: authorize_installation(principal, "platform_services.write")

  def authorize_credential_write(principal, {:tenant, key})
      when is_map(principal) and is_binary(key) do
    authorize_tenant_scoped(principal, "tenant_api_keys.write", key, true)
  end

  def authorize_credential_write(principal, key) when is_map(principal) and is_binary(key) do
    authorize_tenant_scoped(principal, "tenant_api_keys.write", key, true)
  end

  def authorize_credential_write(_principal, _owner), do: {:error, :forbidden}

  @spec service_directory_access(map(), String.t()) ::
          {:ok, {boolean(), boolean()}} | {:error, :forbidden}
  def service_directory_access(principal, tenant_key) do
    service_read? = authorize_tenant_service_read(principal, tenant_key) == :ok
    key_read? = authorize_credential_read(principal, tenant_key) == :ok

    if service_read? or key_read?,
      do: {:ok, {service_read?, key_read?}},
      else: {:error, :forbidden}
  end

  # Identity owns the catalog, scope and membership cap for these actions.
  @spec authorize_tenant_scoped(map(), String.t(), String.t(), boolean()) ::
          :ok | {:error, term()}
  def authorize_tenant_scoped(principal, action, tenant_key, mutating?)
      when is_map(principal) and is_binary(action) and is_binary(tenant_key) and
             is_boolean(mutating?) do
    with :ok <- tenant_key_format(tenant_key) do
      grants = Map.get(principal, :grants) || MapSet.new()
      ctx = context(principal)
      Authorization.authorize(grants, action, {:tenant, tenant_key}, ctx)
      |> map_denial()
    end
  end

  @spec scoped_tenant_list({module(), term()}, map(), pos_integer(), non_neg_integer()) ::
          {:ok, {[map()], non_neg_integer()}} | {:error, term()}
  def scoped_tenant_list(repository, principal, limit, offset) do
    case visible_tenant_scope(principal) do
      :all ->
        Vxpipe.Calls.Repositories.call(repository, :list_tenants, [limit, offset])

      {:assigned, []} ->
        {:ok, {[], 0}}

      {:assigned, keys} ->
        scoped_assigned_list(repository, keys, limit, offset)
    end
  end

  @spec scoped_assigned_list({module(), term()}, [String.t()], pos_integer(), non_neg_integer()) ::
          {:ok, {[map()], non_neg_integer()}} | {:error, term()}
  def scoped_assigned_list(repository, keys, limit, offset)
      when is_list(keys) and is_integer(limit) and is_integer(offset) do
    {module, _context} = repository

    if function_exported?(module, :list_tenants_scoped, 4) do
      Vxpipe.Calls.Repositories.call(repository, :list_tenants_scoped, [
        {:keys, keys},
        limit,
        offset
      ])
    else
      {:error, :repository_unavailable}
    end
  end

  @doc "Authorizes the directory even when a tenant role has no assignments yet."
  @spec authorize_tenant_directory(map()) :: :ok | {:error, :forbidden}
  def authorize_tenant_directory(principal) when is_map(principal) do
    grants = Map.get(principal, :grants) || MapSet.new()

    if authorize_installation(principal, "tenants.read") == :ok or
         authorize_installation(principal, "tenants.write") == :ok or
         Enum.any?(@tenant_actions, &MapSet.member?(grants, &1)),
      do: :ok,
      else: {:error, :forbidden}
  end

  @spec listable_assigned_keys(map()) :: {:ok, [String.t()]} | {:error, :forbidden}
  def listable_assigned_keys(principal) when is_map(principal) do
    keys = assigned_keys(principal)

    if keys == [] do
      {:error, :forbidden}
    else
      grants = Map.get(principal, :grants) || MapSet.new()
      ctx = context(principal)

      visible =
        Enum.filter(keys, fn key ->
          Enum.any?(@tenant_actions, fn action ->
            Authorization.authorize(grants, action, {:tenant, key}, ctx) == :ok
          end)
        end)

      if visible == [], do: {:error, :forbidden}, else: {:ok, visible}
    end
  end

  @spec assigned_keys(map()) :: [String.t()]
  def assigned_keys(principal) when is_map(principal) do
    principal
    |> Map.get(:assigned_tenants, %{})
    |> then(fn
      nil -> []
      assigned when is_map(assigned) -> Map.keys(assigned)
      _ -> []
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.sort()
    |> Enum.uniq()
  end

  @spec validate_listed_tenants([map()], map()) :: :ok | {:error, :tenant_page_unavailable}
  def validate_listed_tenants(tenants, principal) when is_list(tenants) do
    case visible_tenant_scope(principal) do
      :all ->
        :ok

      {:assigned, keys} ->
        allowed = MapSet.new(keys)

        if Enum.all?(tenants, fn
             %{key: key} -> MapSet.member?(allowed, key)
             _ -> false
           end),
           do: :ok,
           else: {:error, :tenant_page_unavailable}
    end
  end

  defp has_all_tenant_grant?(principal) do
    all_tenant = Map.get(principal, :all_tenant_actions) || MapSet.new()

    grants = Map.get(principal, :grants) || MapSet.new()
    Enum.any?(@tenant_actions, &(MapSet.member?(all_tenant, &1) and MapSet.member?(grants, &1)))
  end

  defp tenant_key_format(tenant_key) do
    case Vxpipe.Calls.ProviderAuth.tenant_key(tenant_key) do
      :ok -> :ok
      {:error, :invalid_tenant_key} = error -> error
    end
  end

  defp map_denial(:ok), do: :ok
  defp map_denial({:error, :unknown_action}), do: {:error, :forbidden}
  defp map_denial({:error, :forbidden} = error), do: error
  defp map_denial({:error, _} = error), do: error
end
