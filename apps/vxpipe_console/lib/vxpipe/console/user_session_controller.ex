defmodule Vxpipe.Console.UserSessionController do
  @moduledoc "Returns the current persisted account and role to the Console."

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.UserManagementPayload

  def show(conn, _params) do
    backend =
      Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    case backend.session_details(conn.assigns.user_principal) do
      {:ok, {user, role}} ->
        json(conn, %{
          user: UserManagementPayload.user(user),
          role: UserManagementPayload.role(role)
        })

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: %{code: "unavailable"}})
    end
  end
end
