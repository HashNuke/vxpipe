defmodule Vxpipe.Persistence.IdentityRecord do
  @moduledoc "Shared mapping between identity port maps and Ecto rows."

  import Ecto.Query

  alias Vxpipe.Persistence.Repo

  alias Vxpipe.Persistence.Schema.{
    IdentityMembership,
    IdentityRole,
    IdentityRolePermission,
    IdentitySession,
    IdentityUser,
    Tenant,
    UserAccessEvent
  }

  @spec utc_now() :: DateTime.t()
  def utc_now, do: DateTime.utc_now()

  @spec revalidate_actor(map(), [String.t()] | nil) :: :ok | {:error, :forbidden | :unavailable}
  def revalidate_actor(attrs, required_permissions \\ nil) do
    actor_public_id =
      Map.get(attrs, :actor_user_public_id, Map.get(attrs, "actor_user_public_id"))

    session_public_id =
      Map.get(attrs, :actor_session_public_id, Map.get(attrs, "actor_session_public_id"))

    cond do
      not is_binary(actor_public_id) ->
        {:error, :forbidden}

      not is_binary(session_public_id) ->
        {:error, :forbidden}

      true ->
        case {Ecto.UUID.cast(actor_public_id), Ecto.UUID.cast(session_public_id)} do
          {{:ok, _}, {:ok, _}} ->
            try do
              with {:ok, actor} <- lock_actor_user(actor_public_id),
                   :ok <- check_actor_enabled(actor),
                   :ok <- check_actor_session(actor, attrs),
                   :ok <- check_actor_grants(actor, required_permissions) do
                :ok
              end
            rescue
              _ -> {:error, :unavailable}
            end

          _ ->
            {:error, :forbidden}
        end
    end
  end

  defp lock_actor_user(public_id) when is_binary(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} ->
        case Repo.one(
               from(u in IdentityUser,
                 where: u.public_id == ^public_id,
                 lock: "FOR UPDATE",
                 preload: [:role]
               )
             ) do
          nil -> {:error, :forbidden}
          user -> {:ok, user}
        end

      :error ->
        {:error, :forbidden}
    end
  end

  defp lock_actor_user(_), do: {:error, :forbidden}

  defp check_actor_enabled(%{disabled_at: nil}), do: :ok
  defp check_actor_enabled(_), do: {:error, :forbidden}

  defp check_actor_session(actor, attrs) do
    session_public_id =
      Map.get(attrs, :actor_session_public_id, Map.get(attrs, "actor_session_public_id"))

    cond do
      not is_binary(session_public_id) ->
        {:error, :forbidden}

      Ecto.UUID.cast(session_public_id) == :error ->
        {:error, :forbidden}

      true ->
        now = utc_now()

        case Repo.one(
               from(s in IdentitySession,
                 where: s.public_id == ^session_public_id
               )
             ) do
          nil ->
            {:error, :forbidden}

          session ->
            cond do
              session.user_id != actor.id -> {:error, :forbidden}
              not is_nil(session.revoked_at) -> {:error, :forbidden}
              DateTime.compare(session.expires_at, now) != :gt -> {:error, :forbidden}
              true -> :ok
            end
        end
    end
  end

  defp check_actor_grants(_actor, nil), do: :ok
  defp check_actor_grants(_actor, []), do: :ok

  defp check_actor_grants(actor, required) when is_list(required) do
    grants = effective_grants(actor.role, actor.id)

    if Enum.all?(required, &MapSet.member?(grants, &1)) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp effective_grants(%{kind: kind}, _role_id) when kind in ["superadmin", "admin"] do
    atom = if kind == "superadmin", do: :superadmin, else: :admin
    Vxpipe.Identity.Permission.builtin_grants(atom)
  end

  defp effective_grants(%{id: role_id}, _actor_id) when is_integer(role_id) do
    Repo.all(
      from(g in IdentityRolePermission,
        where: g.role_id == ^role_id,
        select: g.permission_key
      )
    )
    |> MapSet.new()
  end

  defp effective_grants(_, _), do: MapSet.new()

  @spec insert_audit(map() | nil) :: :ok | {:error, term()}
  def insert_audit(nil), do: :ok

  def insert_audit(event) when is_map(event) do
    summary = event |> Map.get(:summary, %{}) |> Vxpipe.Identity.Audit.sanitize_summary()

    changeset =
      UserAccessEvent.changeset(%UserAccessEvent{}, %{
        actor_user_id: lookup_user_id(Map.get(event, :actor_user_public_id)),
        target_user_id: lookup_user_id(Map.get(event, :target_user_public_id)),
        target_role_id: lookup_role_id(Map.get(event, :target_role_public_id)),
        action: to_string(Map.get(event, :action, "unknown")),
        summary: summary
      })

    case Repo.insert(changeset) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp lookup_user_id(nil), do: nil

  defp lookup_user_id(public_id) when is_binary(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} ->
        Repo.one(from(u in IdentityUser, where: u.public_id == ^public_id, select: u.id))

      :error ->
        nil
    end
  end

  defp lookup_user_id(_), do: nil

  defp lookup_role_id(nil), do: nil

  defp lookup_role_id(public_id) when is_binary(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} ->
        Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id, select: r.id))

      :error ->
        nil
    end
  end

  defp lookup_role_id(_), do: nil

  @spec role_kind(String.t() | nil) :: :member | :admin | :superadmin
  def role_kind("superadmin"), do: :superadmin
  def role_kind("admin"), do: :admin
  def role_kind(_), do: :member

  @spec load_memberships(integer()) :: %{String.t() => :read | :read_write}
  def load_memberships(user_id) do
    Repo.all(
      from(m in IdentityMembership,
        join: t in assoc(m, :tenant),
        where: m.user_id == ^user_id,
        select: {t.key, m.access_level}
      )
    )
    |> Map.new(fn {key, level} -> {key, access_level(level)} end)
  end

  @spec user_port_map(map(), map()) :: map()
  def user_port_map(user, memberships) do
    role = user.role

    %{
      public_id: user.public_id,
      email: user.email,
      normalized_email: user.normalized_email,
      password_hash: user.password_hash,
      role_public_id: role.public_id,
      role_kind: role_kind(role.kind),
      role_slug: role.slug,
      disabled_at: user.disabled_at,
      memberships: memberships
    }
  end

  @spec role_port_map(map()) :: map()
  def role_port_map(role) do
    kind = role_kind(role.kind)

    grants =
      case kind do
        :superadmin -> Vxpipe.Identity.Permission.builtin_grant_defs(:superadmin)
        :admin -> Vxpipe.Identity.Permission.builtin_grant_defs(:admin)
        _ -> current_grants(role.id)
      end

    %{
      public_id: role.public_id,
      slug: role.slug,
      name: role.name,
      description: role.description,
      kind: kind,
      revision: role.revision,
      grants: grants
    }
  end

  @spec current_grants(integer()) :: [%{permission: String.t(), scope: atom()}]
  def current_grants(role_id) do
    Repo.all(
      from(g in IdentityRolePermission,
        where: g.role_id == ^role_id,
        select: {g.permission_key, g.scope}
      )
    )
    |> Enum.map(fn {permission, scope} ->
      %{permission: permission, scope: grant_scope(scope)}
    end)
  end

  @spec fetch_role_by_public_id(String.t()) :: {:ok, map()} | {:error, :unknown_role}
  def fetch_role_by_public_id(public_id) do
    case Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id)) do
      nil -> {:error, :unknown_role}
      role -> {:ok, role}
    end
  end

  @spec replace_memberships(integer(), map()) :: :ok | {:error, term()}
  def replace_memberships(user_id, memberships) when is_map(memberships) do
    with {:ok, tenant_ids} <- resolve_tenant_keys(Map.keys(memberships)) do
      _ = Repo.delete_all(from(m in IdentityMembership, where: m.user_id == ^user_id))

      rows =
        Enum.map(memberships, fn {key, level} ->
          %{
            user_id: user_id,
            tenant_id: Map.fetch!(tenant_ids, to_string(key)),
            access_level: access_string(level),
            inserted_at: utc_now()
          }
        end)

      _ = if rows != [], do: Repo.insert_all(IdentityMembership, rows), else: {0, nil}
      :ok
    end
  end

  @spec resolve_tenant_keys([term()]) :: {:ok, map()} | {:error, :unknown_tenant}
  def resolve_tenant_keys([]), do: {:ok, %{}}

  def resolve_tenant_keys(keys) do
    string_keys = Enum.map(keys, &to_string/1)

    found =
      Repo.all(from(t in Tenant, where: t.key in ^string_keys, select: {t.key, t.id}))
      |> Map.new()

    missing = string_keys -- Map.keys(found)

    if missing == [] do
      {:ok, found}
    else
      {:error, :unknown_tenant}
    end
  end

  @spec access_string(atom() | String.t()) :: String.t()
  def access_string(:read), do: "read"
  def access_string(:read_write), do: "read_write"
  def access_string("read"), do: "read"
  def access_string("read_write"), do: "read_write"

  @spec access_level(String.t()) :: :read | :read_write
  def access_level("read_write"), do: :read_write
  def access_level(_), do: :read

  @spec grant_scope(String.t()) :: :installation | :all_tenants | :assigned_tenants
  def grant_scope("all_tenants"), do: :all_tenants
  def grant_scope("assigned_tenants"), do: :assigned_tenants
  def grant_scope(_), do: :installation
end
