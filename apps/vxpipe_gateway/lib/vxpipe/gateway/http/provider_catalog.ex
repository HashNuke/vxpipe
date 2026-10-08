defmodule Vxpipe.Gateway.HTTP.ProviderCatalog do
  @moduledoc false
  import Plug.Conn
  alias Vxpipe.Calls.ProviderCatalogErrors

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
    with {:ok, secret} <- bearer(conn),
         {:ok, author} <- backend(options, :authenticate, [:tenant, tenant, secret]),
         {:ok, result} <- backend(options, function, [author, tenant | arguments]) do
      json(conn, 200, result)
    else
      {:error, reason} ->
        {status, error} = ProviderCatalogErrors.response(reason)
        json(conn, status, %{error: error})
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> secret] when byte_size(secret) in 1..256 -> {:ok, secret}
      _invalid -> {:error, :invalid_api_key}
    end
  end

  defp backend(options, function, arguments) do
    {module, context} = options.backend
    apply(module, function, [context | arguments])
  rescue
    _exception -> {:error, :provider_catalog_unavailable}
  catch
    :exit, _reason -> {:error, :provider_catalog_unavailable}
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
