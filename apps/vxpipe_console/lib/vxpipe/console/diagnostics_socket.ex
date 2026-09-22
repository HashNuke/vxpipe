defmodule Vxpipe.Console.DiagnosticsSocket do
  @moduledoc false

  use Phoenix.LiveView.Socket

  alias Vxpipe.Console.{DiagnosticsEnabled, InstallationOperatorSession, TelephonyHostGuard}

  @impl Phoenix.Socket
  def connect(_params, socket, connect_info) do
    session = Map.get(connect_info, :session, %{})
    host = connect_info |> Map.get(:uri) |> uri_host()

    if not TelephonyHostGuard.public_host?(host) and DiagnosticsEnabled.enabled?() and
         InstallationOperatorSession.fetch_session(session) != :error do
      {:ok, socket}
    else
      :error
    end
  end

  defp uri_host(%URI{host: host}) when is_binary(host), do: host
  defp uri_host(_uri), do: ""

  @impl Phoenix.Socket
  def id(socket), do: Phoenix.LiveView.Socket.id(socket)
end
