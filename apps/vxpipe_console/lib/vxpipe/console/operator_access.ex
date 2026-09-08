defmodule Vxpipe.Console.OperatorAccess do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    if Keyword.fetch!(diagnostics, :enabled) and
         Keyword.fetch!(diagnostics, :access) == :loopback and loopback?(conn.remote_ip) do
      conn
    else
      conn
      |> send_resp(404, "not found")
      |> halt()
    end
  end

  defp loopback?({127, _second, _third, _fourth}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_remote_ip), do: false
end
