defmodule Vxpipe.Console.Endpoint do
  use Phoenix.Endpoint, otp_app: :vxpipe_console

  @session_options [
    store: :cookie,
    key: "_vxpipe_console_key",
    signing_salt: "vxpipe-console"
  ]

  socket "/diagnostics/live", Vxpipe.Console.DiagnosticsSocket,
    websocket: [connect_info: [session: @session_options]]

  plug Vxpipe.Console.GatewayMount

  plug Plug.Static,
    at: "/",
    from: :vxpipe_console,
    gzip: false,
    only: ["assets"],
    cache_control_for_etags: "public, max-age=31536000, immutable"

  plug Plug.Session, @session_options
  plug Vxpipe.Console.Router
end
