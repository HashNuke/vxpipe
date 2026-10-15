defmodule Vxpipe.Console.ProductAPIAuthentication do
  @moduledoc "Browser-session authentication for the shared product HTTP API."

  alias Plug.Conn
  alias Vxpipe.Console.{BrowserSession, UserSession}

  def authenticate(conn, _options) do
    conn =
      conn
      |> BrowserSession.call([])
      |> Conn.fetch_session()
      |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))

    backend =
      Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    case UserSession.fetch(conn, backend: backend) do
      {:ok, principal} ->
        {:ok, conn, principal}

      {:error, _reason} ->
        conn =
          conn
          |> UserSession.clear()
          |> Conn.put_resp_header("cache-control", "no-store")
          |> Conn.put_resp_content_type("application/json")
          |> Conn.send_resp(401, JSON.encode!(%{error: %{code: "session_required"}}))
          |> Conn.halt()

        {:halt, conn}
    end
  end
end
