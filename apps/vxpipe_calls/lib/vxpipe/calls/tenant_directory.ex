defmodule Vxpipe.Calls.TenantDirectory do
  @moduledoc "Visible tenant lookup, search and bounded post-login selection for user principals."

  alias Vxpipe.Calls.{ProviderAuth, Repositories, Tenant, TenantPage, UserAuthorization}
  alias Vxpipe.Identity.Principal

  def navigation(%Principal{} = principal, options) do
    scope = UserAuthorization.visible_tenant_scope(principal)
    directory_access = UserAuthorization.authorize_tenant_directory(principal) == :ok

    with {:ok, candidates} <- landing_candidates(scope, principal, options) do
      {:ok,
       %{
         scope: if(scope == :all, do: :all, else: :assigned),
         directory_access: directory_access,
         landing_tenant:
           case candidates do
             [tenant] -> tenant
             _ -> nil
           end
       }}
    end
  end

  def fetch(%Principal{} = principal, key, options) do
    with :ok <- ProviderAuth.tenant_key(key),
         true <- visible?(principal, key),
         {:ok, tenants} <- candidates(principal, {:keys, [key]}, 1, options) do
      case tenants do
        [%Tenant{key: ^key} = tenant] -> {:ok, tenant}
        [] -> {:error, :tenant_not_found}
        _ -> {:error, :tenant_page_unavailable}
      end
    else
      false -> {:error, :tenant_not_found}
      {:error, :invalid_tenant_key} -> {:error, :tenant_not_found}
      error -> error
    end
  end

  def search(%Principal{} = principal, options) do
    with :ok <- UserAuthorization.authorize_tenant_directory(principal),
         {:ok, query, page, limit} <- search_options(options),
         {:ok, {tenants, total}} <- search_rows(principal, query, page, limit, options),
         :ok <- validate_rows(tenants, principal, limit),
         true <- is_integer(total) and total >= length(tenants) do
      pages = if total == 0, do: 0, else: div(total + limit - 1, limit)

      if page <= max(pages, 1) do
        {:ok,
         %TenantPage{
           tenants: tenants,
           page: page,
           page_size: limit,
           total: total,
           total_pages: pages
         }}
      else
        {:error, :tenant_page_out_of_range}
      end
    else
      false -> {:error, :tenant_page_unavailable}
      {:ok, _invalid} -> {:error, :tenant_page_unavailable}
      error -> error
    end
  end

  defp landing_candidates(:all, _principal, _options), do: {:ok, []}
  defp landing_candidates({:assigned, []}, _principal, _options), do: {:ok, []}

  defp landing_candidates({:assigned, keys}, principal, options),
    do: candidates(principal, {:keys, keys}, 2, options)

  defp candidates(principal, scope, limit, options) do
    with {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         {:ok, tenants} <- invoke(repository, :tenant_candidates, [scope, limit]),
         :ok <- validate_rows(tenants, principal, limit) do
      {:ok, tenants}
    end
  end

  defp search_rows(principal, query, page, limit, options) do
    case UserAuthorization.visible_tenant_scope(principal) do
      {:assigned, []} ->
        {:ok, {[], 0}}

      scope ->
        storage_scope =
          case scope do
            :all -> :all
            {:assigned, keys} -> {:keys, keys}
          end

        with {:ok, repository} <- Repositories.fetch(options, :admin_repository) do
          invoke(repository, :search_tenants, [storage_scope, query, limit, (page - 1) * limit])
        end
    end
  end

  defp validate_rows(tenants, principal, limit) when is_list(tenants) do
    if length(tenants) <= limit and Enum.all?(tenants, &match?(%Tenant{}, &1)),
      do: UserAuthorization.validate_listed_tenants(tenants, principal),
      else: {:error, :tenant_page_unavailable}
  end

  defp validate_rows(_tenants, _principal, _limit), do: {:error, :tenant_page_unavailable}

  defp visible?(principal, key) do
    case UserAuthorization.visible_tenant_scope(principal) do
      :all -> true
      {:assigned, keys} -> key in keys
    end
  end

  defp search_options(options) do
    query = Keyword.get(options, :query, "")
    page = Keyword.get(options, :page, 1)
    limit = Keyword.get(options, :limit, 25)

    with {:ok, query} <- normalize_query(query),
         true <- is_integer(page) and page in 1..2_147_483_647,
         true <- is_integer(limit) and limit in 1..50 do
      {:ok, query, page, limit}
    else
      _ -> {:error, :invalid_tenant_page_request}
    end
  end

  defp normalize_query(query) when is_binary(query) do
    if String.valid?(query) do
      query = String.trim(query)

      if String.length(query) <= 120 and not String.contains?(query, <<0>>),
        do: {:ok, query},
        else: :error
    else
      :error
    end
  end

  defp normalize_query(_query), do: :error

  defp invoke({module, _context} = repository, function, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args) + 1),
      do: Repositories.call(repository, function, args),
      else: {:error, :repository_unavailable}
  end
end
