defmodule Vxpipe.Identity.Principal do
  @moduledoc "Explicit user authority carried on each request. Never fabricated from client claims."

  alias Vxpipe.Identity.{ApiKeyActor, Permission}

  @enforce_keys [:user_public_id, :session_public_id, :account_kind, :grants]
  defstruct [
    :user_public_id,
    :session_public_id,
    :account_kind,
    :grants,
    :assigned_tenants,
    :all_tenant_actions,
    :oauth_grant_public_id,
    :authorization_version,
    :role_public_id,
    :role_revision,
    :delegation,
    credential_kind: :browser_session
  ]

  @type t :: %__MODULE__{
          user_public_id: String.t(),
          session_public_id: String.t() | nil,
          credential_kind: :browser_session | :oauth,
          oauth_grant_public_id: String.t() | nil,
          authorization_version: pos_integer() | nil,
          role_public_id: String.t() | nil,
          role_revision: pos_integer() | nil,
          delegation: map() | nil,
          account_kind: :member | :admin | :superadmin,
          grants: MapSet.t(String.t()),
          assigned_tenants: %{String.t() => :read | :read_write},
          all_tenant_actions: MapSet.t(String.t())
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_principal}
  def new(attrs) when is_map(attrs) do
    with {:ok, user_id} <- fetch_id(attrs, :user_public_id),
         {:ok, credential} <- credential(attrs),
         {:ok, kind} <- fetch_kind(attrs),
         {:ok, grants} <- fetch_grants(attrs) do
      {:ok,
       %__MODULE__{
         user_public_id: user_id,
         session_public_id: credential.session_id,
         credential_kind: credential.kind,
         oauth_grant_public_id: credential.grant_id,
         authorization_version: Map.get(attrs, :authorization_version),
         role_public_id: Map.get(attrs, :role_public_id),
         role_revision: Map.get(attrs, :role_revision),
         delegation: Map.get(attrs, :delegation),
         account_kind: kind,
         grants: grants,
         assigned_tenants: Map.get(attrs, :assigned_tenants, %{}),
         all_tenant_actions: Map.get(attrs, :all_tenant_actions, MapSet.new())
       }}
    else
      _ -> {:error, :invalid_principal}
    end
  end

  def new(_attrs), do: {:error, :invalid_principal}

  def for_session(user, role, session) do
    user
    |> identity_attrs(role)
    |> Map.put(:session_public_id, session.public_id)
    |> new()
  end

  def for_oauth_grant(user, role, grant_id) do
    user
    |> identity_attrs(role)
    |> Map.merge(%{credential_kind: :oauth, oauth_grant_public_id: grant_id})
    |> new()
  end

  defp credential(attrs) do
    case Map.get(attrs, :credential_kind, :browser_session) do
      :browser_session ->
        with {:ok, session_id} <- fetch_id(attrs, :session_public_id),
             true <-
               is_nil(Map.get(attrs, :oauth_grant_public_id)) and
                 is_nil(Map.get(attrs, :delegation)) do
          {:ok, %{kind: :browser_session, session_id: session_id, grant_id: nil}}
        end

      :oauth ->
        grant_id = Map.get(attrs, :oauth_grant_public_id)

        if ApiKeyActor.valid_id?(grant_id) and is_nil(Map.get(attrs, :session_public_id)),
          do: {:ok, %{kind: :oauth, session_id: nil, grant_id: grant_id}},
          else: :error

      _unknown ->
        :error
    end
  end

  defp fetch_id(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_kind(%{account_kind: kind}) when kind in [:member, :admin, :superadmin],
    do: {:ok, kind}

  defp fetch_kind(_), do: :error

  defp fetch_grants(%{grants: %MapSet{} = grants}), do: {:ok, grants}
  defp fetch_grants(%{grants: grants}) when is_list(grants), do: {:ok, MapSet.new(grants)}
  defp fetch_grants(_), do: :error

  defp identity_attrs(user, role) do
    %{
      user_public_id: user.public_id,
      authorization_version: Map.get(user, :authorization_version),
      role_public_id: Map.get(role, :public_id),
      role_revision: Map.get(role, :revision),
      account_kind: role_kind(role),
      grants: grants_for(role),
      assigned_tenants: Map.get(user, :memberships, %{}),
      all_tenant_actions: all_tenant_actions(role)
    }
  end

  defp role_kind(%{kind: kind}) when kind in [:member, :admin, :superadmin], do: kind
  defp role_kind(_), do: :member

  defp grants_for(%{kind: kind}) when kind in [:superadmin, :admin] do
    Permission.builtin_grants(kind)
  end

  defp grants_for(%{grants: grants}) when is_list(grants) do
    grants
    |> Enum.map(&grant_permission/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp grants_for(_), do: MapSet.new()

  defp grant_permission(%{permission: permission}) when is_binary(permission), do: permission
  defp grant_permission(%{"permission" => permission}) when is_binary(permission), do: permission
  defp grant_permission(_), do: nil

  defp operational_all_tenant do
    [
      "calls.read",
      "calls.write",
      "call_specs.read",
      "call_specs.write",
      "tenant_services.read",
      "tenant_services.write",
      "tenant_api_keys.write",
      "access_keys.read",
      "access_keys.write"
    ]
  end

  defp all_tenant_actions(%{kind: kind}) when kind in [:superadmin, :admin] do
    MapSet.new(operational_all_tenant())
  end

  defp all_tenant_actions(%{grants: grants}) when is_list(grants) do
    grants
    |> Enum.filter(&all_tenant_grant?/1)
    |> Enum.map(&grant_permission/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp all_tenant_actions(_), do: MapSet.new()

  defp all_tenant_grant?(%{scope: :all_tenants}), do: true
  defp all_tenant_grant?(%{"scope" => "all_tenants"}), do: true
  defp all_tenant_grant?(_), do: false
end
