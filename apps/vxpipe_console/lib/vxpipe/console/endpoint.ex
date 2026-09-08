defmodule Vxpipe.Console.Endpoint do
  use Phoenix.Endpoint, otp_app: :vxpipe_console

  plug Vxpipe.Console.GatewayMount
  plug Vxpipe.Console.Router
end
