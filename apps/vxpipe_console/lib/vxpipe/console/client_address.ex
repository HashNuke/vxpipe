defmodule Vxpipe.Console.ClientAddress do
  @moduledoc """
  Resolves the browser client's address for identity throttling.

  Public installations reach the Console only through a reverse proxy on the same
  host, so `remote_ip` is loopback for every visitor. Like `TrustedProxyScheme`, the
  forwarded address is trusted only from a loopback peer; the proxy appends the
  address it accepted the connection from as the last `X-Forwarded-For` entry.
  """

  alias Plug.Conn

  @loopback_addresses [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]

  @spec for_throttling(Conn.t()) :: String.t()
  def for_throttling(%Conn{remote_ip: remote_ip} = conn) when remote_ip in @loopback_addresses do
    conn
    |> Conn.get_req_header("x-forwarded-for")
    |> forwarded_client()
    |> Kernel.||(remote_ip)
    |> format()
  end

  def for_throttling(%Conn{remote_ip: remote_ip}), do: format(remote_ip)

  defp forwarded_client([]), do: nil

  defp forwarded_client(values) do
    values
    |> Enum.flat_map(&String.split(&1, ","))
    |> List.last()
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_strict_address()
    |> case do
      {:ok, address} -> address
      {:error, _reason} -> nil
    end
  end

  defp format(address), do: address |> :inet.ntoa() |> to_string()
end
