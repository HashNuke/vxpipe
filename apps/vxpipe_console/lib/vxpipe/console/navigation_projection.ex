defmodule Vxpipe.Console.NavigationProjection do
  @moduledoc "Public destinations and exact capabilities for the authenticated Console shell."

  alias Vxpipe.Calls.UserAuthorization

  def build(principal, selected_key, options \\ []) do
    with {:ok, navigation} <- Vxpipe.Calls.tenant_navigation(principal, options),
         {:ok, tenant} <- selected_tenant(principal, selected_key, options) do
      {:ok,
       %{
         actor: %{id: principal.user_public_id, kind: principal.account_kind},
         tenant_scope: navigation.scope,
         directory_access: navigation.directory_access,
         directory_path: directory_path(navigation.scope),
         landing_path: landing_path(navigation),
         platform_destinations: platform_destinations(principal, navigation.scope),
         tenant: tenant
       }}
    end
  end

  def tenant(principal, tenant) do
    %{
      key: tenant.key,
      name: tenant.name,
      dashboard_path: dashboard_path(tenant.key),
      capabilities:
        Map.new(
          [
            {:calls, "calls"},
            {:call_specs, "call_specs"},
            {:services, "tenant_services"},
            {:api_keys, "tenant_api_keys"}
          ],
          fn {name, action} ->
            {name,
             %{
               read:
                 UserAuthorization.authorize_tenant(principal, action <> ".read", tenant.key) ==
                   :ok,
               write:
                 UserAuthorization.authorize_tenant(principal, action <> ".write", tenant.key) ==
                   :ok
             }}
          end
        )
    }
  end

  def dashboard_path(key), do: "/t/#{URI.encode(key, &URI.char_unreserved?/1)}/dashboard"

  defp selected_tenant(_principal, nil, _options), do: {:ok, nil}

  defp selected_tenant(principal, key, options) do
    with {:ok, tenant} <- Vxpipe.Calls.fetch_visible_tenant(principal, key, options),
         do: {:ok, tenant(principal, tenant)}
  end

  defp directory_path(:all), do: "/tenants"
  defp directory_path(:assigned), do: "/my-tenants"

  defp landing_path(%{landing_tenant: nil, scope: scope}), do: directory_path(scope)
  defp landing_path(%{landing_tenant: tenant}), do: dashboard_path(tenant.key)

  defp platform_destinations(principal, scope) do
    [
      {scope == :all, %{id: "tenants", label: "Tenants", path: "/tenants"}},
      {principal.account_kind in [:admin, :superadmin],
       %{id: "roles", label: "Roles", path: "/roles"}},
      {installed?(principal, "users.read"), %{id: "users", label: "Users", path: "/users"}},
      {installed?(principal, "platform_services.read"),
       %{id: "services", label: "Services", path: "/platform/services"}}
    ]
    |> Enum.flat_map(fn {allowed, destination} -> if allowed, do: [destination], else: [] end)
  end

  defp installed?(principal, action),
    do: UserAuthorization.authorize_installation(principal, action) == :ok
end
