defmodule Vxpipe.Console.OperatorLiveAuthentication do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias Vxpipe.Console.OperatorSession

  def on_mount(:default, _params, session, socket) do
    case OperatorSession.fetch_live(session) do
      {:ok, principal} -> {:cont, assign(socket, :principal, principal)}
      :error -> {:halt, redirect(socket, to: "/operator/sign-in")}
    end
  end
end
