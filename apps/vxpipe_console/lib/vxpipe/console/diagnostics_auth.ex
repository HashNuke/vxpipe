defmodule Vxpipe.Console.DiagnosticsAuth do
  @moduledoc false

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias Vxpipe.Console.{DiagnosticsEnabled, UserSession}

  def on_mount(:default, _params, session, socket) do
    if DiagnosticsEnabled.enabled?() and authorized?(session) do
      socket =
        socket
        |> attach_hook(:diagnostics_session_info, :handle_info, fn _message, socket ->
          continue_if_authorized(session, socket)
        end)
        |> attach_hook(:diagnostics_session_event, :handle_event, fn _event, _params, socket ->
          continue_if_authorized(session, socket)
        end)
        |> attach_hook(:diagnostics_session_params, :handle_params, fn _params, _uri, socket ->
          continue_if_authorized(session, socket)
        end)

      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/auth/login")}
    end
  end

  defp continue_if_authorized(session, socket) do
    if DiagnosticsEnabled.enabled?() and authorized?(session) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/auth/login")}
    end
  end

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
end
