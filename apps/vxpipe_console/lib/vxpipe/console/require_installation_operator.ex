defmodule Vxpipe.Console.RequireInstallationOperator do
  @moduledoc "Requires an unexpired installation-wide operator session for HTML."

  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]

  alias Plug.Conn
  alias Vxpipe.Console.{InstallationOperatorSession, OperatorSession}

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{} = conn, _options) do
    conn = OperatorSession.clear(conn)

    case InstallationOperatorSession.fetch(conn) do
      {:ok, grant} ->
        Conn.assign(conn, :installation_operator, grant)

      :error ->
        conn
        |> InstallationOperatorSession.clear()
        |> redirect(to: "/auth/login")
        |> Conn.halt()
    end
  end
end
