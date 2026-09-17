defmodule Vxpipe.Console.Endpoint do
  use Phoenix.Endpoint, otp_app: :vxpipe_console

  @session_options [
    store: :cookie,
    key: "_vxpipe_console_key",
    signing_salt: "vxpipe-console",
    same_site: "Lax"
  ]

  socket "/diagnostics/live", Vxpipe.Console.DiagnosticsSocket,
    websocket: [connect_info: [session: @session_options]]

  socket "/calls/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
  end

  plug Vxpipe.Console.TrustedProxyScheme
  plug Vxpipe.Console.OperatorResponseHeaders
  plug Vxpipe.Console.OperatorTraffic
  plug Vxpipe.Console.GatewayMount

  plug Plug.Static,
    at: "/",
    from: :vxpipe_console,
    gzip: false,
    only: ["assets"],
    cache_control_for_etags: "public, max-age=0, must-revalidate"

  if code_reloading? do
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.Session, @session_options
  plug Vxpipe.Console.Router
end
