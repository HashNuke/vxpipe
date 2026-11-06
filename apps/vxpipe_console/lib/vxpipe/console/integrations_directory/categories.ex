defmodule Vxpipe.Console.IntegrationsDirectory.Categories do
  @moduledoc "Authorized, bounded traversal of the public category taxonomy."
  alias Vxpipe.Calls.UserAuthorization
  alias Vxpipe.Console.IntegrationsDirectory.{Cache, Request}

  def list(principal, tenant, options \\ []) do
    with :ok <- UserAuthorization.authorize_tenant_service_read(principal, tenant),
         {:ok, categories} <-
           collect(Keyword.get(options, :fetcher, &Cache.fetch/2), nil, nil, [], MapSet.new(), 0) do
      {:ok,
       %{
         categories: Enum.sort_by(categories, &{&1["order"], &1["id"]}),
         installation_version: Request.installation_version()
       }}
    end
  end

  defp collect(_fetcher, _cursor, _identity, _items, _seen, count) when count >= 10,
    do: {:error, :directory_too_large}

  defp collect(fetcher, cursor, identity, items, seen, count) do
    params = if cursor, do: %{"limit" => 100, "cursor" => cursor}, else: %{"limit" => 100}

    with {:ok, %{body: page}} <- fetcher.(:categories, params),
         page_identity = Map.take(page, ["directory_id", "revision", "installation_version"]),
         true <- is_nil(identity) or identity == page_identity,
         next_items = items ++ page["items"],
         true <- length(next_items) <= 1000,
         true <- length(Enum.uniq_by(next_items, & &1["id"])) == length(next_items) do
      case page["pagination"]["next_cursor"] do
        nil ->
          {:ok, next_items}

        next ->
          if MapSet.member?(seen, next),
            do: {:error, :invalid_page},
            else:
              collect(fetcher, next, page_identity, next_items, MapSet.put(seen, next), count + 1)
      end
    else
      false -> {:error, :invalid_page}
      {:error, _reason} = error -> error
    end
  end
end
