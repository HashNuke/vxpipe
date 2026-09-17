defmodule Vxpipe.Console.OperatorTraffic do
  @moduledoc "Rejects operator login and admin traffic over public plain HTTP."

  @behaviour Plug

  alias Plug.Conn

  @loopback_hosts ["localhost", "127.0.0.1", "::1"]
  @loopback_addresses [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{} = conn, _options) do
    if operator_path?(conn.path_info) and insecure_public?(conn) do
      conn
      |> Conn.put_resp_content_type("text/plain")
      |> Conn.put_resp_header("cache-control", "private, no-store")
      |> Conn.send_resp(404, "not found")
      |> Conn.halt()
    else
      conn
    end
  end

  defp operator_path?(["auth" | _rest]), do: true
  defp operator_path?(["admin" | _rest]), do: true
  defp operator_path?(_path), do: false

  defp insecure_public?(%Conn{scheme: :https}), do: false

  defp insecure_public?(%Conn{host: host, remote_ip: remote_ip}) do
    String.downcase(host) not in @loopback_hosts or remote_ip not in @loopback_addresses
  end
end
