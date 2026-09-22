defmodule Vxpipe.Console.DiagnosticsAuth do
  @moduledoc false

  import Phoenix.LiveView, only: [redirect: 2]

  alias Vxpipe.Console.{DiagnosticsEnabled, InstallationOperatorSession}

  def on_mount(:default, _params, session, socket) do
    if DiagnosticsEnabled.enabled?() and
         InstallationOperatorSession.fetch_session(session) != :error do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/auth/login")}
    end
  end
end
