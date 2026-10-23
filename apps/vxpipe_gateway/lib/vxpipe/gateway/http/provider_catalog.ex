defmodule Vxpipe.Gateway.HTTP.ProviderCatalog do
  @moduledoc false
  import Plug.Conn
  alias Vxpipe.Calls.ProviderCatalogErrors
  alias Vxpipe.Gateway.CatalogPage
  alias Vxpipe.Gateway.HTTP.{PageQuery, ProductAuthentication}

  def route(conn, %{enabled: false}, _tenant, _segments), do: send_resp(conn, 404, "not found")

  def route(%{method: "GET"} = conn, options, tenant, []) do
    conn = fetch_query_params(conn)
    handle(conn, options, tenant, :providers, [Map.get(conn.query_params, "capability")])
  end

  def route(%{method: "GET"} = conn, options, tenant, [provider, "models"]) do
    conn = fetch_query_params(conn)
    handle(conn, options, tenant, :models, [provider, Map.get(conn.query_params, "capability")])
  end

  def route(conn, _options, _tenant, _segments), do: send_resp(conn, 404, "not found")

  defp handle(conn, options, tenant, function, arguments) do
    case ProductAuthentication.authenticate(conn, options.browser_auth, fn secret ->
           backend(options, :authenticate, [:tenant, tenant, secret])
         end) do
      {:ok, conn, author} -> perform(conn, options, author, tenant, function, arguments)
      {:halt, conn} -> conn
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :provider_catalog_unavailable)
    end
  end

  defp perform(conn, options, author, tenant, function, arguments) do
    with {:ok, pagination} <- pagination(conn.query_params),
         {:ok, result} <- backend(options, function, [author, tenant | arguments]),
         {:ok, result} <- project(result, function, pagination) do
      json(conn, 200, result)
    else
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :provider_catalog_unavailable)
    end
  end

  defp pagination(params) do
    if Map.has_key?(params, "page") or Map.has_key?(params, "page_size") do
      with {:ok, page, size} <- PageQuery.parse(Map.take(params, ["page", "page_size"])),
           do: {:ok, {page, size}}
    else
      {:ok, :unpaged}
    end
  end

  defp project(result, _function, :unpaged) when is_map(result), do: {:ok, result}

  defp project(result, function, {page, size}) when is_map(result) do
    case Map.fetch(result, function) do
      {:ok, items} when is_list(items) -> CatalogPage.paginate(items, page, size)
      _invalid -> {:error, :provider_catalog_unavailable}
    end
  end

  defp project(_result, _function, _pagination), do: {:error, :provider_catalog_unavailable}

  defp error(conn, reason) do
    {status, error} = ProviderCatalogErrors.response(reason)
    json(conn, status, %{error: error})
  end

  defp backend(options, function, arguments) do
    {module, context} = options.backend
    apply(module, function, [context | arguments])
  rescue
    _exception -> {:error, :provider_catalog_unavailable}
  catch
    _kind, _reason -> {:error, :provider_catalog_unavailable}
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
