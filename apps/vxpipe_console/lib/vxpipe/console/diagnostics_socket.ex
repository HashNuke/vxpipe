defmodule Vxpipe.Console.DiagnosticsSocket do
  @moduledoc false

  use Phoenix.LiveView.Socket

  alias Vxpipe.Console.{DiagnosticsEnabled, TelephonyHostGuard, UserSession}

  @impl Phoenix.Socket
  def connect(_params, socket, connect_info) do
    session = Map.get(connect_info, :session, %{})
    host = connect_info |> Map.get(:uri) |> uri_host()

    if not TelephonyHostGuard.public_host?(host) and DiagnosticsEnabled.enabled?() and
         authorized?(session) do
      {:ok, socket}
    else
      :error
    end
  end

  defp uri_host(%URI{host: host}) when is_binary(host), do: host
  defp uri_host(_uri), do: ""

  defp authorized?(session) do
    case UserSession.fetch_session(session, backend: identity_backend()) do
      {:ok, principal} ->
        principal.account_kind == :superadmin

      {:error, _reason} ->
        false
    end
  end

  defp identity_backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

  @impl Phoenix.Socket
  def id(socket), do: Phoenix.LiveView.Socket.id(socket)
end
