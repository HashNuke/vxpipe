defmodule Vxpipe.Console.DiagnosticsEnabled do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options), do: options

  @spec enabled?() :: boolean()
  def enabled? do
    :vxpipe_console
    |> Application.fetch_env!(:diagnostics)
    |> Keyword.fetch!(:enabled)
  end

  @impl true
  def call(conn, _options) do
    if enabled?() do
      conn
    else
      conn
      |> send_resp(404, "not found")
      |> halt()
    end
  end
end
