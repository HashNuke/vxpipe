defmodule Vxpipe.Identity.Principal do
  @moduledoc "Explicit user authority carried on each request. Never fabricated from client claims."

  @enforce_keys [:user_public_id, :session_public_id, :account_kind, :grants]
  defstruct [:user_public_id, :session_public_id, :account_kind, :grants, :assigned_tenants, :all_tenant_actions]

  @type t :: %__MODULE__{
          user_public_id: String.t(),
          session_public_id: String.t(),
          account_kind: :member | :admin | :superadmin,
          grants: MapSet.t(String.t()),
          assigned_tenants: %{String.t() => :read | :read_write},
          all_tenant_actions: MapSet.t(String.t())
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_principal}
  def new(attrs) when is_map(attrs) do
    with {:ok, user_id} <- fetch_id(attrs, :user_public_id),
         {:ok, session_id} <- fetch_id(attrs, :session_public_id),
         {:ok, kind} <- fetch_kind(attrs),
         {:ok, grants} <- fetch_grants(attrs) do
      {:ok,
       %__MODULE__{
         user_public_id: user_id,
         session_public_id: session_id,
         account_kind: kind,
         grants: grants,
         assigned_tenants: Map.get(attrs, :assigned_tenants, %{}),
         all_tenant_actions: Map.get(attrs, :all_tenant_actions, MapSet.new())
       }}
    else
      _ -> {:error, :invalid_principal}
    end
  end

  defp fetch_id(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_kind(%{account_kind: kind}) when kind in [:member, :admin, :superadmin], do: {:ok, kind}
  defp fetch_kind(_), do: :error

  defp fetch_grants(%{grants: %MapSet{} = grants}), do: {:ok, grants}
  defp fetch_grants(%{grants: grants}) when is_list(grants), do: {:ok, MapSet.new(grants)}
  defp fetch_grants(_), do: :error
end
