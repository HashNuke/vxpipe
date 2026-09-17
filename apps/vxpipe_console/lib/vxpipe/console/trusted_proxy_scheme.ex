defmodule Vxpipe.Console.TrustedProxyScheme do
  @moduledoc "Trusts HTTPS forwarding only from a reverse proxy on the same host."

  @behaviour Plug

  alias Plug.Conn

  @loopback_addresses [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{remote_ip: remote_ip} = conn, _options) when remote_ip in @loopback_addresses do
    case Conn.get_req_header(conn, "x-forwarded-proto") do
      ["https"] -> %{conn | scheme: :https, port: 443}
      _other -> conn
    end
  end

  def call(%Conn{} = conn, _options), do: conn
end
