defmodule Vxpipe.Console.OperatorLiveAuthentication do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias Vxpipe.Console.OperatorSession

  def tenant_path?(%{assigns: %{principal: principal}}, %{"tenant_key" => tenant_key}),
    do: tenant_key == principal.tenant_key

  def tenant_path?(_socket, _params), do: false

  def on_mount(:default, %{"tenant_key" => tenant_key}, session, socket) do
    case OperatorSession.fetch_live(session) do
      {:ok, principal} when tenant_key == principal.tenant_key ->
        {:cont, assign(socket, :principal, principal)}

      {:ok, _principal} ->
        {:halt, redirect(socket, to: "/operator/sign-in")}

      :error ->
        {:halt, redirect(socket, to: "/operator/sign-in")}
    end
  end

  def on_mount(:default, _params, _session, socket),
    do: {:halt, redirect(socket, to: "/operator/sign-in")}
end
