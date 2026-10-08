defmodule Vxpipe.Console.Endpoint do
  use Phoenix.Endpoint, otp_app: :vxpipe_console

  socket "/admin/diagnostics/live", Vxpipe.Console.DiagnosticsSocket,
    websocket: [connect_info: [:uri, session: {Vxpipe.Console.BrowserSession, :options, []}]]

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Vxpipe.Console.LiveReloadSocket,
      websocket: [connect_info: [:uri]]
  end

  plug Vxpipe.Console.TrustedProxyScheme
  plug Vxpipe.Console.OperatorResponseHeaders
  plug Vxpipe.Console.OperatorTraffic
  plug Vxpipe.Console.TelephonyHostGuard
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

  plug Vxpipe.Console.BrowserSession
  plug Vxpipe.Console.Router
end
