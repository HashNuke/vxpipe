defmodule Vxpipe.Console.DiagnosticsEnabled do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    diagnostics = Application.fetch_env!(:vxpipe_console, :diagnostics)

    if Keyword.fetch!(diagnostics, :enabled) do
      conn
    else
      conn
      |> send_resp(404, "not found")
      |> halt()
    end
  end
end
