defmodule Vxpipe.Console.OperatorLoginController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.{
    InstallationOperatorSession,
    OperatorLoginConfiguration,
    OperatorLoginCredentials,
    OperatorLoginPage
  }

  def guidance(conn, _params) do
    case InstallationOperatorSession.fetch(conn) do
      {:ok, _grant} -> redirect(conn, to: "/admin")
      :error -> html(conn, page(OperatorLoginPage.guidance(%{})))
    end
  end

  def new(conn, %{"token" => token}) do
    html(
      conn,
      page(
        OperatorLoginPage.code(%{
          csrf_token: Plug.CSRFProtection.get_csrf_token(),
          token: token
        })
      )
    )
  end

  def create(conn, _params) do
    with {:ok, token, code} <- OperatorLoginCredentials.fetch(conn),
         true <- token != "",
         {:ok, verifier_secret} <- OperatorLoginConfiguration.verifier_secret(),
         :ok <- Vxpipe.Calls.consume_operator_login_challenge(token, code, verifier_secret) do
      conn
      |> clear_session()
      |> configure_session(renew: true)
      |> InstallationOperatorSession.put()
      |> redirect(to: "/admin")
    else
      _invalid -> unavailable(conn)
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: "/auth/login")
  end

  defp unavailable(conn) do
    conn
    |> put_status(422)
    |> html(page(OperatorLoginPage.unavailable(%{})))
  end

  defp page(content), do: Phoenix.HTML.Safe.to_iodata(content)
end
