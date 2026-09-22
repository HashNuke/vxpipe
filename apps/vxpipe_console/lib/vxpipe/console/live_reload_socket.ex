defmodule Vxpipe.Console.LiveReloadSocket do
  @moduledoc false

  use Phoenix.Socket, log: false

  alias Vxpipe.Console.TelephonyHostGuard

  channel "phoenix:live_reload", Phoenix.LiveReloader.Channel

  @impl Phoenix.Socket
  def connect(_params, socket, connect_info) do
    host = connect_info |> Map.get(:uri) |> uri_host()

    if TelephonyHostGuard.public_host?(host) do
      :error
    else
      {:ok, socket}
    end
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil

  defp uri_host(%URI{host: host}) when is_binary(host), do: host
  defp uri_host(_uri), do: ""
end
