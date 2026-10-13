defmodule Vxpipe.Console.RequireUser do
  @moduledoc "Authenticates browser pages and checks their page-level access."

  @behaviour Plug

  import Phoenix.Controller, only: [redirect: 2]

  alias Plug.Conn
  alias Vxpipe.Console.{InstallationOperatorSession, UserSession}
  alias Vxpipe.Identity.Authorization

  @impl true
  def init(options), do: options

  @impl true
  def call(%Conn{} = conn, options) do
    conn = conn |> InstallationOperatorSession.clear() |> Conn.delete_session("vxpipe_operator")
    backend = Keyword.get(options, :backend, identity_backend())

    case UserSession.fetch(conn, backend: backend) do
      {:ok, principal} ->
        if permitted?(principal, conn.path_info) do
          Conn.assign(conn, :user_principal, principal)
        else
          conn |> Conn.send_resp(403, "Forbidden") |> Conn.halt()
        end

      {:error, _} ->
        conn |> UserSession.clear() |> redirect(to: "/auth/login") |> Conn.halt()
    end
  end

  defp permitted?(_principal, ["admin"]), do: true
  defp permitted?(_principal, ["admin", "account"]), do: true

  defp permitted?(principal, ["admin", "users" | _]),
    do: installed?(principal, "users.read")

  defp permitted?(principal, ["admin", "roles" | _]),
    do: principal.account_kind in [:admin, :superadmin]

  defp permitted?(principal, ["admin", "platform", "services"]),
    do: installed?(principal, "platform_services.read")

  defp permitted?(principal, ["admin", "onboarding"]),
    do: installed?(principal, "tenants.write")

  defp permitted?(principal, ["admin", "diagnostics" | _]),
    do: installed?(principal, "diagnostics.read")

  defp permitted?(principal, ["admin", "samples" | _]),
    do: installed?(principal, "tenants.write")

  defp permitted?(principal, ["admin", "tenants", tenant, "call-specs" | _]),
    do: tenant?(principal, "call_specs.read", tenant)

  defp permitted?(principal, ["admin", "tenants", tenant, "calls" | _]),
    do: tenant?(principal, "calls.read", tenant)

  defp permitted?(principal, ["admin", "tenants", tenant, "services" | _]),
    do: tenant?(principal, "tenant_services.read", tenant)

  defp permitted?(_principal, ["admin", "tenants", _tenant]), do: true

  defp permitted?(principal, ["tenants", tenant, "calls" | _]),
    do: tenant?(principal, "calls.read", tenant)

  defp permitted?(_principal, _path), do: false

  defp installed?(principal, action),
    do: Authorization.authorize(principal.grants, action, :installation) == :ok

  defp tenant?(principal, action, tenant),
    do: Authorization.authorize(principal.grants, action, {:tenant, tenant}, principal) == :ok

  defp identity_backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
