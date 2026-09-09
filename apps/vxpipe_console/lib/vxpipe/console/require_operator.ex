defmodule Vxpipe.Console.RequireOperator do
  @moduledoc "Requires an unexpired calls-scoped Console operator session."

  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]

  alias Plug.Conn
  alias Vxpipe.Console.OperatorSession

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{} = conn, _options) do
    case OperatorSession.fetch(conn) do
      {:ok, principal} ->
        Conn.assign(conn, :operator_principal, principal)

      :error ->
        conn
        |> OperatorSession.clear()
        |> redirect(to: "/operator/sign-in")
        |> Conn.halt()
    end
  end
end
