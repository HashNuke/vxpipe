defmodule Vxpipe.Console.LegacyOperatorSessionController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.OperatorSession

  def guidance(conn, _params) do
    conn
    |> OperatorSession.clear()
    |> redirect(to: "/auth/login")
  end

  def reject(conn, _params) do
    conn
    |> OperatorSession.clear()
    |> put_status(:gone)
    |> put_resp_header("cache-control", "private, no-store")
    |> text("Tenant API-key UI sign-in has been retired.")
  end
end
