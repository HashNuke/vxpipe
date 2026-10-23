defmodule Vxpipe.Gateway.HTTP.AccountManagement do
  @moduledoc "Authenticated canonical account HTTP operations; Identity owns account policy."

  import Plug.Conn
  alias Vxpipe.Calls
  alias Vxpipe.Gateway.{AccountErrors, AccountJSON, AccountManagement}
  alias Vxpipe.Gateway.HTTP.ProductAuthentication

  def init(options) do
    %{
      enabled: Keyword.get(options, :enabled, false),
      browser_auth: Keyword.get(options, :browser_auth),
      calls_options: Keyword.get(options, :calls_options, []),
      identity_options: Keyword.get(options, :identity_options, [])
    }
  end

  def route(conn, %{enabled: false}, _segments), do: send_resp(conn, 404, "not found")

  def route(conn, options, segments) do
    case safely(fn ->
           ProductAuthentication.authenticate(conn, options.browser_auth, fn secret ->
             Calls.authenticate_api_key(secret, options.calls_options)
           end)
         end) do
      {:ok, conn, actor} -> perform(conn, options.identity_options, actor, segments)
      {:halt, conn} -> conn
      {:error, reason} -> error(conn, reason)
      _invalid -> error(conn, :unavailable)
    end
  end

  defp perform(%{method: "GET"} = conn, options, actor, ["users"]) do
    conn = fetch_query_params(conn)

    respond(
      conn,
      AccountManagement.list_users(actor, conn.query_params, options),
      &AccountJSON.user_page(&1, :http)
    )
  end

  defp perform(%{method: "GET"} = conn, options, actor, ["role-options"]) do
    conn = fetch_query_params(conn)

    respond(
      conn,
      AccountManagement.list_role_options(actor, conn.query_params, options),
      &AccountJSON.role_page(&1, :http)
    )
  end

  defp perform(%{method: "GET"} = conn, options, actor, ["users", id]),
    do: respond(conn, AccountManagement.get_user(actor, id, options), &user/1)

  defp perform(%{method: "POST"} = conn, options, actor, ["users"]),
    do:
      respond(conn, AccountManagement.create_user(actor, conn.body_params, options), &user/1, 201)

  defp perform(%{method: "PATCH"} = conn, options, actor, ["users", id]),
    do:
      respond(conn, AccountManagement.update_user(actor, id, conn.body_params, options), &user/1)

  defp perform(%{method: "POST"} = conn, options, actor, ["users", id, "disable"]) do
    if conn.body_params == %{},
      do: respond(conn, AccountManagement.disable_user(actor, id, options), &user/1),
      else: error(conn, :invalid_account)
  end

  defp perform(conn, _options, _actor, _segments), do: send_resp(conn, 404, "not found")

  defp user(record), do: %{user: AccountJSON.user(record, :http)}

  defp respond(conn, result, projection, status \\ 200)

  defp respond(conn, {:ok, result}, projection, status),
    do: json(conn, status, projection.(result))

  defp respond(conn, {:error, reason}, _projection, _status), do: error(conn, reason)
  defp respond(conn, _invalid, _projection, _status), do: error(conn, :unavailable)

  defp error(conn, reason) do
    {status, error} = AccountErrors.response(reason)
    json(conn, status, %{error: error})
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp safely(operation) do
    operation.()
  rescue
    error in Plug.CSRFProtection.InvalidCSRFTokenError -> reraise error, __STACKTRACE__
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end
end
