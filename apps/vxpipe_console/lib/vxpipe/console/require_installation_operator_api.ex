defmodule Vxpipe.Console.RequireInstallationOperatorAPI do
  @moduledoc "Requires an unexpired installation-wide operator session for JSON."

  @behaviour Plug

  import Phoenix.Controller, only: [json: 2]

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
        |> Conn.put_status(401)
        |> json(%{error: %{code: "operator_session_required"}})
        |> Conn.halt()
    end
  end
end
