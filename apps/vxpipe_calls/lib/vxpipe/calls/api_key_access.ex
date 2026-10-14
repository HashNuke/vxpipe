defmodule Vxpipe.Calls.ApiKeyAccess do
  @moduledoc "Permission scopes for Vxpipe access-key management and delegation."
  alias Vxpipe.Calls.UserAuthorization

  @full_actions ~w(calls.read calls.write call_specs.read call_specs.write tenant_services.read tenant_services.write tenant_api_keys.write access_keys.read access_keys.write)

  def scope(principal, mode) when mode in [:read, :write, :calls, :full] do
    actions = actions(mode)
    all = principal.all_tenant_actions || MapSet.new()

    if Enum.all?(actions, &(MapSet.member?(principal.grants, &1) and MapSet.member?(all, &1))) do
      :all
    else
      keys =
        (principal.assigned_tenants || %{})
        |> Map.keys()
        |> Enum.filter(&allowed?(principal, actions, &1))
        |> Enum.sort()

      {:keys, keys}
    end
  end

  def platform_read?(principal),
    do: UserAuthorization.authorize_installation(principal, "platform_api_keys.read") == :ok

  def platform_write?(principal),
    do:
      principal.account_kind == :superadmin and
        UserAuthorization.authorize_installation(principal, "platform_api_keys.write") == :ok

  def visible?(principal), do: platform_read?(principal) or scope(principal, :read) != {:keys, []}

  def authorize_create(principal, "platform", nil),
    do: if(platform_write?(principal), do: :ok, else: {:error, :forbidden})

  def authorize_create(principal, kind, tenant)
      when kind in ["calls", "full"] and is_binary(tenant) do
    mode = if kind == "calls", do: :calls, else: :full
    if allowed?(principal, actions(mode), tenant), do: :ok, else: {:error, :forbidden}
  end

  def authorize_create(_principal, _kind, _tenant), do: {:error, :invalid_key_type}

  def authorize_write(principal, nil),
    do: if(platform_write?(principal), do: :ok, else: {:error, :forbidden})

  def authorize_write(principal, tenant),
    do: UserAuthorization.authorize_tenant(principal, "access_keys.write", tenant)

  defp actions(:read), do: ["access_keys.read"]
  defp actions(:write), do: ["access_keys.write"]
  defp actions(:calls), do: ["access_keys.write", "calls.write"]
  defp actions(:full), do: @full_actions

  defp allowed?(principal, actions, tenant),
    do: Enum.all?(actions, &(UserAuthorization.authorize_tenant(principal, &1, tenant) == :ok))
end
