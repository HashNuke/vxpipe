defmodule Vxpipe.Identity.Authorization do
  @moduledoc """
  Pure authorization policy. Exact key matching only; unknown actions deny.
  Tenant grants are capped by membership access levels.
  """

  alias Vxpipe.Identity.Permission

  @type account_kind :: :member | :admin | :superadmin
  @type tenant_access :: :read | :read_write
  @type context :: %{
          optional(:assigned_tenants) => %{String.t() => tenant_access()},
          optional(:all_tenant_actions) => MapSet.t(String.t())
        }

  @spec require_account_write(MapSet.t(String.t()), account_kind(), account_kind()) ::
          :ok | {:error, :forbidden}
  def require_account_write(actor_grants, current_kind, requested_kind) do
    with :ok <- require_kind(actor_grants, current_kind),
         :ok <- require_kind(actor_grants, requested_kind) do
      :ok
    end
  end

  @spec require_account_create(MapSet.t(String.t()), account_kind()) ::
          :ok | {:error, :forbidden}
  def require_account_create(actor_grants, target_kind) do
    require_kind(actor_grants, target_kind)
  end

  @spec require_actor_identity(map()) :: :ok | {:error, :forbidden}
  def require_actor_identity(actor) when is_map(actor) do
    with {:ok, user_id} <- fetch_actor_id(actor, [:user_public_id, "user_public_id"]),
         {:ok, session_id} <- fetch_actor_id(actor, [:session_public_id, "session_public_id"]),
         true <- uuid_shaped?(user_id),
         true <- uuid_shaped?(session_id) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def require_actor_identity(_), do: {:error, :forbidden}

  defp fetch_actor_id(actor, keys) do
    Enum.find_value(keys, :error, fn key ->
      case Map.fetch(actor, key) do
        {:ok, value} when is_binary(value) -> {:ok, value}
        _ -> nil
      end
    end)
    |> case do
      {:ok, _} = ok -> ok
      _ -> :error
    end
  end

  defp uuid_shaped?(value) when is_binary(value) do
    Regex.match?(
      ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/,
      value
    )
  end

  defp uuid_shaped?(_), do: false

  defp require_kind(grants, kind) do
    required = Permission.account_kind_permission(kind)
    if MapSet.member?(grants, required), do: :ok, else: {:error, :forbidden}
  end

  @spec authorize(MapSet.t(String.t()), String.t(), term(), context()) ::
          :ok | {:error, :unknown_action | :forbidden}
  def authorize(grants, action, resource, context \\ %{})

  def authorize(_grants, action, _resource, _context) when not is_binary(action) do
    {:error, :unknown_action}
  end

  def authorize(grants, action, resource, context) do
    case Permission.fetch(action) do
      {:error, :unknown_permission} ->
        {:error, :unknown_action}

      {:ok, entry} ->
        authorize_entry(grants, entry, resource, context)
    end
  end

  defp authorize_entry(grants, %{key: key, scopes: scopes}, :installation, _context) do
    cond do
      :installation not in scopes -> {:error, :forbidden}
      MapSet.member?(grants, key) -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp authorize_entry(grants, %{key: key} = entry, {:tenant, tenant_id}, context)
       when is_binary(tenant_id) do
    assigned = Map.get(context, :assigned_tenants, %{})
    all_tenant = Map.get(context, :all_tenant_actions, MapSet.new())

    cond do
      MapSet.member?(grants, key) and MapSet.member?(all_tenant, key) and
          all_tenant_applies?(entry) ->
        :ok

      true ->
        case Map.fetch(assigned, tenant_id) do
          {:ok, level} ->
            if MapSet.member?(grants, key) and assigned_applies?(entry) and
                 cap_allows?(entry, level) do
              :ok
            else
              {:error, :forbidden}
            end

          :error ->
            {:error, :forbidden}
        end
    end
  end

  defp authorize_entry(_grants, _entry, _resource, _context), do: {:error, :forbidden}

  defp all_tenant_applies?(%{scopes: scopes}), do: :all_tenants in scopes

  defp assigned_applies?(%{scopes: scopes}), do: :assigned_tenants in scopes

  defp cap_allows?(%{mutating: false}, :read), do: true
  defp cap_allows?(%{mutating: true}, :read), do: false
  defp cap_allows?(_entry, :read_write), do: true
  defp cap_allows?(_entry, _level), do: false
end
