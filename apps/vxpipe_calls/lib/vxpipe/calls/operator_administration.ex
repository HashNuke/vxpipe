defmodule Vxpipe.Calls.OperatorAdministration do
  @moduledoc "Installation-wide, bounded read workflows for the operator application."

  alias Vxpipe.Calls.{InstallationOperator, Repositories, TenantPage}

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

  defp total_pages(0, _limit), do: 0
  defp total_pages(total, limit), do: div(total + limit - 1, limit)

  defp page_range(page, total, limit) do
    pages = total_pages(total, limit)

    if page <= max(pages, 1),
      do: {:ok, pages},
      else: {:error, :tenant_page_out_of_range}
  end
end
