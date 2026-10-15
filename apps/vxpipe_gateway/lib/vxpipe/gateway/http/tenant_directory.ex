defmodule Vxpipe.Gateway.HTTP.TenantDirectory do
  @moduledoc "Canonical tenant directory and lookup HTTP projections."

  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Tenant, TenantPage}
  alias Vxpipe.Gateway.HTTP.ProductAuthentication
  alias Vxpipe.Gateway.TenantJSON

  def init(options) do
    %{
      enabled: Keyword.get(options, :enabled, false),
      browser_auth: Keyword.get(options, :browser_auth),
      calls_options: Keyword.get(options, :calls_options, [])
    }
  end

  def index(conn, %{enabled: false}), do: send_resp(conn, 404, "not found")

  def index(conn, options) do
    conn = fetch_query_params(conn)

    case authenticate(conn, options) do
      {:ok, conn, actor} -> list(conn, options, actor)
      {:halt, conn} -> conn
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :repository_unavailable)
    end
  end

  def show(conn, %{enabled: false}, _key), do: send_resp(conn, 404, "not found")

  def show(conn, options, key) do
    case authenticate(conn, options) do
      {:ok, conn, actor} -> fetch(conn, options, actor, key)
      {:halt, conn} -> conn
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :repository_unavailable)
    end
  end

  defp list(conn, options, actor) do
    with {:ok, query} <- query(conn.query_params),
         {:ok, %TenantPage{} = page} <-
           safely(fn -> Calls.search_operator_tenants(actor, query ++ options.calls_options) end) do
      json(conn, 200, TenantJSON.page(page))
    else
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :repository_unavailable)
    end
  end

  defp fetch(conn, options, actor, key) do
    case safely(fn -> Calls.fetch_visible_tenant(actor, key, options.calls_options) end) do
      {:ok, %Tenant{} = result} -> json(conn, 200, TenantJSON.tenant(result))
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :repository_unavailable)
    end
  end

  defp authenticate(conn, options) do
    ProductAuthentication.authenticate(conn, options.browser_auth, fn secret ->
      safely(fn -> Calls.authenticate_api_key(secret, options.calls_options) end)
    end)
  end

  defp query(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["q", "page", "page_size"])),
         {:ok, page} <- integer(Map.get(params, "page", "1")),
         {:ok, size} <- integer(Map.get(params, "page_size", "25")) do
      {:ok, [query: Map.get(params, "q", ""), page: page, limit: size]}
    else
      _invalid -> {:error, :invalid_tenant_page_request}
    end
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> {:error, :invalid_tenant_page_request}
    end
  end

  defp integer(_value), do: {:error, :invalid_tenant_page_request}

  defp error(conn, :invalid_api_key), do: problem(conn, 401, "invalid_api_key")
  defp error(conn, :forbidden), do: problem(conn, 403, "forbidden")
  defp error(conn, :tenant_not_found), do: problem(conn, 404, "tenant_not_found")

  defp error(conn, :invalid_tenant_page_request),
    do: problem(conn, 422, "invalid_tenant_page_request")

  defp error(conn, :tenant_page_out_of_range), do: problem(conn, 422, "page_out_of_range")
  defp error(conn, _reason), do: problem(conn, 503, "tenant_directory_unavailable")

  defp problem(conn, status, code), do: json(conn, status, %{error: %{code: code}})

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp safely(operation) do
    operation.()
  rescue
    _error -> {:error, :repository_unavailable}
  catch
    :exit, _reason -> {:error, :repository_unavailable}
    :throw, _reason -> {:error, :repository_unavailable}
  end
end
