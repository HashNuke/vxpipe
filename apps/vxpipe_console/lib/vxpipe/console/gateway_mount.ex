defmodule Vxpipe.Console.GatewayMount do
  @moduledoc false

  @behaviour Plug

  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.HTTP.Mount

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    if Vxpipe.Console.SessionProductAPI.route?(conn) do
      conn
    else
      Mount.call(conn, Endpoint.config(:gateway_mount))
    end
  end
end
