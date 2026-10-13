defmodule Vxpipe.Console.AccountController do
  @moduledoc "Self-service account changes confirmed with the current password."

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.UserManagementPayload

  def update(conn, params) do
    case backend().update_account(
           conn.assigns.user_principal,
           Map.get(params, "current_password"),
           Map.get(params, "email"),
           Map.get(params, "password"),
           Map.get(params, "password_confirmation")
         ) do
      {:ok, user} -> json(conn, %{user: UserManagementPayload.user(user)})
      {:error, :invalid_credentials} -> error(conn, 401, "invalid_credentials")
      {:error, :unavailable} -> error(conn, 503, "unavailable")
      {:error, _reason} -> error(conn, 422, "invalid_account")
    end
  end

  defp error(conn, status, code), do: conn |> put_status(status) |> json(%{error: %{code: code}})

  defp backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
