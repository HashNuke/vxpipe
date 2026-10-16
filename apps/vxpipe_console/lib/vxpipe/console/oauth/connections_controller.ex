defmodule Vxpipe.Console.OAuth.ConnectionsController do
  @moduledoc "Session-only connected client management for the current account."
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Identity.Principal

  def index(conn, _params) do
    with {:ok, principal} <- principal(conn),
         {:ok, grants} <- backend().list_grants(principal) do
      connections =
        Enum.map(
          grants,
          &Map.take(&1, [:public_id, :client_name, :resource, :inserted_at, :expires_at])
        )

      json(conn, %{connections: connections})
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, principal} <- principal(conn), :ok <- backend().revoke_grant(principal, id) do
      send_resp(conn, 204, "")
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp principal(%{
         assigns: %{user_principal: %Principal{credential_kind: :browser_session} = principal}
       }),
       do: {:ok, principal}

  defp principal(_conn), do: {:error, :forbidden}

  defp backend,
    do:
      Application.get_env(:vxpipe_console, :oauth, [])
      |> Keyword.get(:backend, Vxpipe.Identity.OAuth)

  defp failure(conn, reason) do
    {status, code} =
      case reason do
        :forbidden -> {403, "forbidden"}
        :not_found -> {404, "not_found"}
        _ -> {503, "unavailable"}
      end

    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end
