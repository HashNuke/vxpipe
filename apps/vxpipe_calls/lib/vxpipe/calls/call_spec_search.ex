defmodule Vxpipe.Calls.CallSpecSearch do
  @moduledoc "Tenant-scoped, paginated call spec choices for the calls directory."

  alias Vxpipe.Calls.{ProviderAuth, Repositories, UserAuthorization}
  alias Vxpipe.Identity.Principal

  def search(%Principal{} = principal, tenant_key, query, page, options \\ []) do
    with :ok <- ProviderAuth.tenant_key(tenant_key),
         :ok <- UserAuthorization.authorize_tenant(principal, "calls.read", tenant_key),
         :ok <- validate(query, page),
         {:ok, repository} <- Repositories.fetch(options, :admin_repository) do
      Repositories.call(repository, :search_call_specs, [
        tenant_key,
        String.trim(query),
        25,
        (page - 1) * 25
      ])
    end
  end

  defp validate(query, page)
       when is_binary(query) and byte_size(query) <= 256 and is_integer(page) and page > 0,
       do: :ok

  defp validate(_query, _page), do: {:error, :invalid_search}
end
