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
        conn
        |> UserSession.clear()
        |> Conn.put_session("vxpipe_return_path", conn.request_path <> query_suffix(conn))
        |> redirect(to: "/auth/login")
        |> Conn.halt()
    end
  end

  def allowed_path?(principal, path) when is_binary(path) do
    uri = URI.parse(path)

    is_nil(uri.scheme) and is_nil(uri.host) and String.starts_with?(path, "/") and
      not String.starts_with?(path, "//") and not String.contains?(path, ["\\", "\r", "\n"]) and
      permitted?(principal, String.split(uri.path || "", "/", trim: true))
  end

  def allowed_path?(_principal, _path), do: false

  defp query_suffix(conn) do
    conn = Conn.fetch_query_params(conn)

    query =
      conn.query_params
      |> Map.take(["page", "q", "role", "call_spec_id"])
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)
      |> URI.encode_query()

    if query == "", do: "", else: "?" <> query
  end

  defp permitted?(principal, ["tenants", "new"]), do: installed?(principal, "tenants.write")
  defp permitted?(principal, ["getting-started"]), do: installed?(principal, "tenants.write")
  defp permitted?(_principal, ["admin"]), do: true
  defp permitted?(_principal, [directory]) when directory in ["tenants", "my-tenants"], do: true
  defp permitted?(_principal, ["t", _tenant, "dashboard"]), do: true

  defp permitted?(principal, [section | rest])
       when section in ["account", "users", "roles", "platform"],
       do: permitted?(principal, ["admin", section | rest])

  defp permitted?(principal, ["t", tenant, resource])
       when resource in ["calls", "call-specs", "services"],
       do: permitted?(principal, ["admin", "tenants", tenant, resource])

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
    do:
      tenant?(principal, "tenant_services.read", tenant) or
        tenant?(principal, "tenant_api_keys.read", tenant)

  defp permitted?(principal, ["admin", "tenants", tenant, "setup-services"]),
    do: permitted?(principal, ["admin", "tenants", tenant, "services"])

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
