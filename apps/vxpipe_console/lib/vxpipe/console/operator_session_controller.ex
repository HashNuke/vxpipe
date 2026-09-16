defmodule Vxpipe.Console.OperatorSessionController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.{OperatorAuthentication, OperatorSession, OperatorSignInPage}

  def new(conn, _params) do
    case OperatorSession.fetch(conn) do
      {:ok, principal} -> redirect(conn, to: calls_path(principal.tenant_key))
      :error -> render_page(conn, 200, nil, "")
    end
  end

  def create(conn, %{
        "operator" => %{"tenant_key" => tenant_key, "api_key" => api_key}
      }) do
    case OperatorAuthentication.authenticate(tenant_key, api_key) do
      {:ok, principal} ->
        conn
        |> configure_session(renew: true)
        |> OperatorSession.put(principal)
        |> redirect(to: calls_path(principal.tenant_key))

      {:error, _reason} ->
        render_page(
          conn,
          422,
          "Credentials were not accepted. Check both values and try again.",
          tenant_key
        )
    end
  end

  def create(conn, _params) do
    render_page(conn, 422, "Credentials were not accepted. Check both values and try again.", "")
  end

  def delete(conn, _params) do
    conn
    |> OperatorSession.clear()
    |> configure_session(drop: true)
    |> redirect(to: "/operator/sign-in")
  end

  defp render_page(conn, status, error, tenant_key) do
    content =
      OperatorSignInPage.render(%{
        csrf_token: Plug.CSRFProtection.get_csrf_token(),
        error: error,
        tenant_key: tenant_key
      })

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> html(Phoenix.HTML.Safe.to_iodata(content))
  end

  defp calls_path(tenant_key),
    do: "/tenants/#{URI.encode_www_form(tenant_key)}/calls"
end
