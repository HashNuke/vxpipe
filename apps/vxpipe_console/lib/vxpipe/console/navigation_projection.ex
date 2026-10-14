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
         directory_path: "/tenants",
         landing_path: landing_path(navigation),
         platform_destinations: platform_destinations(principal),
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
                 UserAuthorization.authorize_tenant(principal, read_action(action), tenant.key) ==
                   :ok,
               write:
                 UserAuthorization.authorize_tenant(principal, action <> ".write", tenant.key) ==
                   :ok
             }}
          end
        )
    }
  end

  defp read_action("tenant_api_keys"), do: "tenant_services.read"
  defp read_action(action), do: action <> ".read"

  def dashboard_path(key), do: "/t/#{URI.encode(key, &URI.char_unreserved?/1)}/dashboard"

  defp selected_tenant(_principal, nil, _options), do: {:ok, nil}

  defp selected_tenant(principal, key, options) do
    with {:ok, tenant} <- Vxpipe.Calls.fetch_visible_tenant(principal, key, options),
         do: {:ok, tenant(principal, tenant)}
  end

  defp landing_path(%{landing_tenant: nil}), do: "/tenants"
  defp landing_path(%{landing_tenant: tenant}), do: dashboard_path(tenant.key)

  defp platform_destinations(principal) do
    [
      {Vxpipe.Calls.ApiKeyAccess.visible?(principal),
       %{id: "api_keys", label: "API Keys", path: "/api-keys"}},
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
