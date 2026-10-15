defmodule Vxpipe.Gateway.HTTP.CallSpecReads do
  @moduledoc "Canonical authenticated call-spec directory and portable source reads."

  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallSpecErrors, CallSpecPage}
  alias Vxpipe.Gateway.CallSpecJSON
  alias Vxpipe.Gateway.HTTP.{PageQuery, ProductAuthentication}

  def init(options) do
    %{
      enabled: Keyword.get(options, :enabled, false),
      browser_auth: Keyword.get(options, :browser_auth),
      calls_options: Keyword.get(options, :calls_options, [])
    }
  end

  def route(conn, %{enabled: false}, _tenant, _segments), do: send_resp(conn, 404, "not found")

  def route(%{method: "GET"} = conn, options, tenant, segments) when length(segments) <= 1 do
    conn = fetch_query_params(conn)

    case authenticate(conn, options) do
      {:ok, conn, actor} ->
        respond(conn, perform(actor, tenant, segments, conn.query_params, options))

      {:halt, conn} ->
        conn

      {:error, reason} ->
        respond(conn, {:error, reason})

      _invalid ->
        respond(conn, {:error, :repository_unavailable})
    end
  end

  def route(conn, _options, _tenant, _segments), do: send_resp(conn, 404, "not found")

  defp perform(actor, tenant, [], params, options) do
    safely(fn ->
      with {:ok, page, limit} <- PageQuery.parse(params),
           {:ok, %CallSpecPage{} = result} <-
             Calls.list_operator_call_specs(
               actor,
               tenant,
               [page: page, limit: limit] ++ options.calls_options
             ) do
        {:ok, CallSpecJSON.page(result)}
      end
    end)
  end

  defp perform(actor, tenant, [id], params, options) do
    safely(fn ->
      with {:ok, revision} <- revision(params),
           {:ok, result} <-
             Calls.fetch_operator_call_spec(
               actor,
               tenant,
               id,
               [revision: revision] ++ options.calls_options
             ) do
        {:ok, CallSpecJSON.read(result)}
      end
    end)
  end

  defp revision(params) when map_size(params) == 0, do: {:ok, nil}

  defp revision(%{"revision" => input} = params)
       when map_size(params) == 1 and is_binary(input) do
    case Integer.parse(input) do
      {value, ""} when value in 1..2_147_483_647 -> {:ok, value}
      _invalid -> {:error, :invalid_request}
    end
  end

  defp revision(_params), do: {:error, :invalid_request}

  defp authenticate(conn, options) do
    ProductAuthentication.authenticate(conn, options.browser_auth, fn secret ->
      safely(fn -> Calls.authenticate_api_key(secret, options.calls_options) end)
    end)
  end

  defp respond(conn, {:ok, body}), do: json(conn, 200, body)

  defp respond(conn, {:error, reason}) do
    {status, error} = CallSpecErrors.read_response(reason)
    json(conn, status, %{error: error})
  end

  defp respond(conn, _invalid), do: respond(conn, {:error, :repository_unavailable})

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
    _kind, _reason -> {:error, :repository_unavailable}
  end
end
