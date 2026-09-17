defmodule Vxpipe.Calls.OperatorAdministration do
  @moduledoc "Installation-wide, bounded read workflows for the operator application."

  alias Vxpipe.Calls.{
    CallDirectoryPage,
    DefinitionPage,
    InstallationOperator,
    Repositories,
    TenantPage
  }

  @default_page_size 25
  @maximum_page_size 100

  @spec list_tenants(InstallationOperator.t(), keyword()) ::
          {:ok, TenantPage.t()} | {:error, term()}
  def list_tenants(%InstallationOperator{grant: :installation_operator}, options)
      when is_list(options) do
    with {:ok, page} <- positive_integer(options, :page, 1),
         {:ok, limit} <- page_size(options),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         offset = (page - 1) * limit,
         {:ok, {tenants, total}} <-
           Repositories.call(repository, :list_tenants, [limit, offset]),
         {:ok, total_pages} <- page_range(page, total, limit) do
      {:ok,
       %TenantPage{
         tenants: tenants,
         page: page,
         page_size: limit,
         total: total,
         total_pages: total_pages
       }}
    end
  end

  def list_tenants(%InstallationOperator{}, _options),
    do: {:error, :installation_operator_required}

  def list_tenants(_authority, _options), do: {:error, :installation_operator_required}

  @spec list_definitions(InstallationOperator.t(), String.t(), keyword()) ::
          {:ok, DefinitionPage.t()} | {:error, term()}
  def list_definitions(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        options
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and is_list(options) do
    with {:ok, page} <- positive_integer(options, :page, 1),
         {:ok, limit} <- page_size(options),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         offset = (page - 1) * limit,
         {:ok, {tenant, definitions, total}} <-
           Repositories.call(repository, :list_definitions, [tenant_key, limit, offset]),
         {:ok, total_pages} <- page_range(page, total, limit, :definition_page_out_of_range) do
      {:ok,
       %DefinitionPage{
         tenant: tenant,
         definitions: definitions,
         page: page,
         page_size: limit,
         total: total,
         total_pages: total_pages
       }}
    end
  end

  def list_definitions(%InstallationOperator{}, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  def list_definitions(_authority, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  @spec list_calls(InstallationOperator.t(), String.t(), keyword()) ::
          {:ok, CallDirectoryPage.t()} | {:error, term()}
  def list_calls(
        %InstallationOperator{grant: :installation_operator},
        tenant_key,
        options
      )
      when is_binary(tenant_key) and byte_size(tenant_key) > 0 and is_list(options) do
    with {:ok, definition_id} <- definition_filter(options),
         {:ok, page} <- positive_integer(options, :page, 1),
         {:ok, limit} <- page_size(options),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository),
         offset = (page - 1) * limit,
         {:ok, {tenant, definitions, definitions_truncated, calls, total}} <-
           Repositories.call(repository, :list_calls, [
             tenant_key,
             definition_id,
             limit,
             offset
           ]),
         {:ok, total_pages} <- page_range(page, total, limit, :call_page_out_of_range) do
      {:ok,
       %CallDirectoryPage{
         tenant: tenant,
         definitions: definitions,
         definitions_truncated: definitions_truncated,
         selected_definition_id: definition_id,
         calls: calls,
         page: page,
         page_size: limit,
         total: total,
         total_pages: total_pages
       }}
    end
  end

  def list_calls(%InstallationOperator{}, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  def list_calls(_authority, _tenant_key, _options),
    do: {:error, :installation_operator_required}

  defp page_size(options) do
    with {:ok, limit} <- positive_integer(options, :limit, @default_page_size),
         true <- limit <= @maximum_page_size do
      {:ok, limit}
    else
      _invalid -> {:error, :invalid_tenant_page_request}
    end
  end

  defp positive_integer(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_tenant_page_request}
    end
  end

  defp definition_filter(options) do
    case Keyword.get(options, :definition_id) do
      nil ->
        {:ok, nil}

      value when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256 ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_call_directory_request}
    end
  end

  defp total_pages(0, _limit), do: 0
  defp total_pages(total, limit), do: div(total + limit - 1, limit)

  defp page_range(page, total, limit, error \\ :tenant_page_out_of_range) do
    pages = total_pages(total, limit)

    if page <= max(pages, 1),
      do: {:ok, pages},
      else: {:error, error}
  end
end
