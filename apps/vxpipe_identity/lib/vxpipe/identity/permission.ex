defmodule Vxpipe.Identity.Permission do
  @moduledoc """
  Registered permission catalog. Keys match exactly; dots are namespacing
  with no prefix/wildcard inheritance.
  """

  @type scope :: :installation | :all_tenants | :assigned_tenants
  @type entry :: %{
          key: String.t(),
          resource: atom(),
          scopes: [scope()],
          mutating: boolean(),
          requires_read: String.t() | nil,
          reserved: boolean()
        }

  @catalog [
    %{
      key: "calls.read",
      resource: :calls,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "calls.write",
      resource: :calls,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: true,
      requires_read: "calls.read",
      reserved: false
    },
    %{
      key: "call_specs.read",
      resource: :call_specs,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "call_specs.write",
      resource: :call_specs,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: true,
      requires_read: "call_specs.read",
      reserved: false
    },
    %{
      key: "platform_services.read",
      resource: :platform_services,
      scopes: [:installation],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "platform_services.write",
      resource: :platform_services,
      scopes: [:installation],
      mutating: true,
      requires_read: "platform_services.read",
      reserved: false
    },
    %{
      key: "tenant_services.read",
      resource: :tenant_services,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "tenant_services.write",
      resource: :tenant_services,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: true,
      requires_read: "tenant_services.read",
      reserved: false
    },
    %{
      key: "tenant_api_keys.write",
      resource: :tenant_api_keys,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: true,
      requires_read: "tenant_services.read",
      reserved: false
    },
    %{
      key: "access_keys.read",
      resource: :access_keys,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "access_keys.write",
      resource: :access_keys,
      scopes: [:all_tenants, :assigned_tenants],
      mutating: true,
      requires_read: "access_keys.read",
      reserved: false
    },
    %{
      key: "platform_api_keys.read",
      resource: :platform_api_keys,
      scopes: [:installation],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "platform_api_keys.write",
      resource: :platform_api_keys,
      scopes: [:installation],
      mutating: true,
      requires_read: "platform_api_keys.read",
      reserved: true
    },
    %{
      key: "tenants.read",
      resource: :tenants,
      scopes: [:installation],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "tenants.write",
      resource: :tenants,
      scopes: [:installation],
      mutating: true,
      requires_read: "tenants.read",
      reserved: false
    },
    %{
      key: "diagnostics.read",
      resource: :diagnostics,
      scopes: [:installation],
      mutating: false,
      requires_read: nil,
      reserved: true
    },
    %{
      key: "users.read",
      resource: :users,
      scopes: [:installation],
      mutating: false,
      requires_read: nil,
      reserved: false
    },
    %{
      key: "users.members.write",
      resource: :users,
      scopes: [:installation],
      mutating: true,
      requires_read: "users.read",
      reserved: true
    },
    %{
      key: "users.admins.write",
      resource: :users,
      scopes: [:installation],
      mutating: true,
      requires_read: "users.read",
      reserved: true
    },
    %{
      key: "users.superadmins.write",
      resource: :users,
      scopes: [:installation],
      mutating: true,
      requires_read: "users.read",
      reserved: true
    }
  ]

  @by_key Map.new(@catalog, &{&1.key, &1})
  @reserved_keys @catalog |> Enum.filter(& &1.reserved) |> Enum.map(& &1.key) |> MapSet.new()

  @spec catalog() :: [entry()]
  def catalog, do: @catalog

  @spec fetch(String.t()) :: {:ok, entry()} | {:error, :unknown_permission}
  def fetch(key) when is_binary(key) do
    case Map.fetch(@by_key, key) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :unknown_permission}
    end
  end

  @spec reserved?(String.t()) :: boolean()
  def reserved?(key), do: MapSet.member?(@reserved_keys, key)

  @spec reserved_keys() :: MapSet.t(String.t())
  def reserved_keys, do: @reserved_keys

  @spec valid_scope?(String.t(), scope()) :: boolean()
  def valid_scope?(key, scope) do
    case fetch(key) do
      {:ok, %{scopes: scopes}} -> scope in scopes
      _ -> false
    end
  end

  @spec account_kind_permission(:member | :admin | :superadmin) :: String.t()
  def account_kind_permission(:member), do: "users.members.write"
  def account_kind_permission(:admin), do: "users.admins.write"
  def account_kind_permission(:superadmin), do: "users.superadmins.write"

  @operational_grants [
    "calls.read",
    "calls.write",
    "call_specs.read",
    "call_specs.write",
    "platform_services.read",
    "platform_services.write",
    "tenant_services.read",
    "tenant_services.write",
    "tenant_api_keys.write",
    "access_keys.read",
    "access_keys.write",
    "platform_api_keys.read",
    "tenants.read",
    "tenants.write",
    "diagnostics.read"
  ]

  @spec operational_grants() :: [String.t()]
  def operational_grants, do: @operational_grants

  @spec builtin_grants(:superadmin | :admin) :: MapSet.t(String.t())
  def builtin_grants(:superadmin) do
    MapSet.new([
      "users.read",
      "users.members.write",
      "users.admins.write",
      "platform_api_keys.write",
      "users.superadmins.write" | @operational_grants
    ])
  end

  def builtin_grants(:admin) do
    MapSet.new(["users.read", "users.members.write" | @operational_grants])
  end

  @spec builtin_grant_defs(:superadmin | :admin) :: [%{permission: String.t(), scope: scope()}]
  def builtin_grant_defs(kind) when kind in [:superadmin, :admin] do
    kind
    |> builtin_grants()
    |> Enum.map(fn key ->
      scope =
        case fetch(key) do
          {:ok, %{scopes: scopes}} ->
            cond do
              :all_tenants in scopes -> :all_tenants
              :installation in scopes -> :installation
              true -> hd(scopes)
            end

          _ ->
            :installation
        end

      %{permission: key, scope: scope}
    end)
  end
end
