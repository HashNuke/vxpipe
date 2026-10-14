defmodule Vxpipe.Console.RequireUserAPI do
  @moduledoc "Authenticates JSON requests and enforces their exact route permission."

  @behaviour Plug

  import Phoenix.Controller, only: [json: 2]

  alias Plug.Conn
  alias Vxpipe.Console.{RoutePermission, UserSession}
  alias Vxpipe.Identity.Authorization

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{} = conn, options) do
    backend = Keyword.get(options, :backend, identity_backend())

    case UserSession.fetch(conn, backend: backend) do
      {:ok, principal} ->
        case authorize(principal, RoutePermission.for_request(conn.method, conn.path_info)) do
          :ok -> Conn.assign(conn, :user_principal, principal)
          {:error, _} -> reject(conn, 403, "forbidden")
        end

      {:error, _} ->
        conn |> UserSession.clear() |> reject(401, "session_required")
    end
  end

  defp authorize(%{account_kind: :superadmin}, :superadmin), do: :ok
  defp authorize(_principal, :superadmin), do: {:error, :forbidden}

  defp authorize(_principal, :authenticated), do: :ok

  defp authorize(principal, {:installation, permission}) do
    Authorization.authorize(principal.grants, permission, :installation)
  end

  defp authorize(principal, {:tenant, permission, tenant}) do
    Authorization.authorize(principal.grants, permission, {:tenant, tenant}, principal)
  end

  defp authorize(principal, {:directory, "tenants.read"}) do
    Vxpipe.Calls.UserAuthorization.authorize_tenant_directory(principal)
  end

  defp authorize(_principal, _unknown), do: {:error, :unknown_action}

  defp reject(conn, status, code) do
    conn |> Conn.put_status(status) |> json(%{error: %{code: code}}) |> Conn.halt()
  end

  defp identity_backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
