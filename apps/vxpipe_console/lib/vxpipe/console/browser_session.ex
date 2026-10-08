defmodule Vxpipe.Console.BrowserSession do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options), do: Plug.Session.call(conn, Plug.Session.init(options()))

  # The HTTP plug and diagnostics WebSocket use the same runtime-selected cookie.
  def options do
    [
      store: :cookie,
      key: Application.get_env(:vxpipe_console, :session_cookie_name, "_vxpipe_console_key"),
      signing_salt: "vxpipe-console",
      same_site: "Lax"
    ]
  end
end
