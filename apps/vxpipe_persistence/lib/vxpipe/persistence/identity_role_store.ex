defmodule Vxpipe.Persistence.IdentityRoleStore do
  @moduledoc "Ecto adapter for the `Vxpipe.Identity.Ports.Roles` boundary."

  @behaviour Vxpipe.Identity.Ports.Roles

  import Ecto.Query

  alias Vxpipe.Identity.Permission
  alias Vxpipe.Persistence.IdentityRecord
  alias Vxpipe.Persistence.Repo

  alias Vxpipe.Persistence.Schema.{
    AuthenticationInstallation,
    IdentityMembership,
    IdentityRole,
    IdentityRolePermission,
    IdentitySession,
    IdentityUser
  }

  @impl true
  def fetch(public_id) do
    case Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id)) do
      nil -> {:error, :not_found}
      role -> {:ok, IdentityRecord.role_port_map(role)}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def fetch_by_slug(slug) do
    case Repo.one(from(r in IdentityRole, where: r.slug == ^slug)) do
      nil -> {:error, :not_found}
      role -> {:ok, IdentityRecord.role_port_map(role)}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def list do
    {:ok,
     Repo.all(from(r in IdentityRole, order_by: [r.id]))
     |> Enum.map(&IdentityRecord.role_port_map/1)}
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def list_options(filters) do
    with {:ok, filters} <- Vxpipe.Identity.AccountPage.filters(filters) do
      query =
        from(r in IdentityRole,
          order_by: [asc: r.name, asc: r.public_id],
          limit: ^filters.page_size,
          offset: ^((filters.page - 1) * filters.page_size),
          select: %{public_id: r.public_id, name: r.name, kind: r.kind}
        )

      roles =
        Enum.map(Repo.all(query), fn role ->
          Map.update!(role, :kind, fn kind ->
            case kind do
              "admin" -> :admin
              "superadmin" -> :superadmin
              _ -> nil
            end
          end)
        end)

      {:ok, %{roles: roles, total: Repo.aggregate(IdentityRole, :count)}}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def create(attrs) do
    if Map.get(attrs, :kind, Map.get(attrs, "kind")) != nil do
      {:error, :protected_role}
    else
      Repo.transaction(fn ->
        with {:ok, grants} <-
               validate_role_grants(Map.get(attrs, :grants, Map.get(attrs, "grants", []))),
             :ok <- revalidate_role_actor(attrs),
             {:ok, role} <- insert_role(attrs, grants),
             :ok <-
               IdentityRecord.insert_audit(
                 Map.get(attrs, :audit_event, Map.get(attrs, "audit_event"))
               ) do
          IdentityRecord.role_port_map(role)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, role} -> {:ok, role}
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def apply_update(public_id, changes) do
    Repo.transaction(fn ->
      with {:ok, _installation} <- lock_installation(),
           {:ok, role} <- lock_role_by_public_id(public_id),
           :ok <- require_ordinary_role(role),
           :ok <- check_revision(role, changes),
           :ok <- revalidate_role_actor(changes),
           {:ok, grants} <- resolve_grants(role, changes),
           {:ok, updated} <- persist_role_changes(role, changes, grants) do
        now = IdentityRecord.utc_now()
        _ = revoke_role_sessions(updated.id, now)
        _ = maybe_clear_obsolete_memberships(updated.id, grants)

        case IdentityRecord.insert_audit(
               Map.get(changes, :audit_event, Map.get(changes, "audit_event"))
             ) do
          :ok -> IdentityRecord.role_port_map(updated)
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, role} -> {:ok, role}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def delete(public_id) do
    delete(public_id, %{})
  end

  def delete(public_id, opts) when is_map(opts) do
    Repo.transaction(fn ->
      with {:ok, role} <- lock_role_by_public_id(public_id),
           :ok <- require_ordinary_role(role),
           :ok <- revalidate_role_actor(opts),
           0 <- Repo.aggregate(from(u in IdentityUser, where: u.role_id == ^role.id), :count) do
        case Repo.delete(role) do
          {:ok, _} ->
            case IdentityRecord.insert_audit(
                   Map.get(opts, :audit_event, Map.get(opts, "audit_event"))
                 ) do
              :ok -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end

          {:error, _} ->
            Repo.rollback(:role_in_use)
        end
      else
        count when is_integer(count) and count > 0 -> Repo.rollback(:role_in_use)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def count_users(public_id) do
    case Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id, select: r.id)) do
      nil ->
        {:error, :not_found}

      role_id ->
        {:ok, Repo.aggregate(from(u in IdentityUser, where: u.role_id == ^role_id), :count)}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp lock_installation do
    case Repo.get(AuthenticationInstallation, "default", lock: "FOR UPDATE") do
      nil -> {:error, :missing}
      installation -> {:ok, installation}
    end
  end

  defp revalidate_role_actor(attrs) do
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
            with :ok <- IdentityRecord.revalidate_actor(attrs, nil),
                 {:ok, kind} <- actor_account_kind(actor_public_id) do
              if kind in [:superadmin, :admin], do: :ok, else: {:error, :forbidden}
            end

          _ ->
            {:error, :forbidden}
        end
    end
  end

  defp actor_account_kind(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} ->
        case Repo.one(
               from(u in IdentityUser,
                 join: r in assoc(u, :role),
                 where: u.public_id == ^public_id,
                 select: r.kind
               )
             ) do
          nil -> {:error, :forbidden}
          "superadmin" -> {:ok, :superadmin}
          "admin" -> {:ok, :admin}
          _ -> {:ok, :member}
        end

      :error ->
        {:error, :forbidden}
    end
  end

  defp lock_role_by_public_id(public_id) do
    case Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id, lock: "FOR UPDATE")) do
      nil -> {:error, :not_found}
      role -> {:ok, role}
    end
  end

  defp require_ordinary_role(%IdentityRole{kind: kind}) when kind in ["superadmin", "admin"] do
    {:error, :protected_role}
  end

  defp require_ordinary_role(_), do: :ok

  defp check_revision(role, changes) do
    expected = Map.get(changes, :expected_revision, Map.get(changes, "expected_revision"))

    cond do
      is_integer(expected) and expected >= 1 and expected == role.revision -> :ok
      true -> {:error, :stale_revision}
    end
  end

  defp resolve_grants(role, changes) do
    cond do
      Map.has_key?(changes, :grants) -> validate_role_grants(Map.get(changes, :grants))
      Map.has_key?(changes, "grants") -> validate_role_grants(Map.get(changes, "grants"))
      true -> validate_role_grants(IdentityRecord.current_grants(role.id))
    end
  end

  defp validate_role_grants(grants) when is_list(grants) do
    Enum.reduce_while(grants, {:ok, []}, fn grant, {:ok, acc} ->
      permission = Map.get(grant, :permission, Map.get(grant, "permission"))
      scope = Map.get(grant, :scope, Map.get(grant, "scope"))

      with {:ok, scope_atom} <- normalize_scope(scope),
           {:ok, entry} <- Permission.fetch(permission),
           true <- scope_atom in entry.scopes,
           false <- Permission.reserved?(permission) do
        {:cont, {:ok, [%{permission: permission, scope: Atom.to_string(scope_atom)} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
        false -> {:halt, {:error, :invalid_scope}}
        true -> {:halt, {:error, :reserved_permission}}
      end
    end)
    |> case do
      {:ok, normalized} -> check_grant_dependencies(Enum.reverse(normalized))
      error -> error
    end
  end

  defp validate_role_grants(_), do: {:error, :invalid_grants}

  defp normalize_scope(:installation), do: {:ok, :installation}
  defp normalize_scope(:all_tenants), do: {:ok, :all_tenants}
  defp normalize_scope(:assigned_tenants), do: {:ok, :assigned_tenants}
  defp normalize_scope("installation"), do: {:ok, :installation}
  defp normalize_scope("all_tenants"), do: {:ok, :all_tenants}
  defp normalize_scope("assigned_tenants"), do: {:ok, :assigned_tenants}
  defp normalize_scope(_), do: {:error, :invalid_scope}

  defp check_grant_dependencies(grants) do
    keys = Enum.map(grants, & &1.permission)

    if length(keys) != length(Enum.uniq(keys)) do
      {:error, :overlapping_scopes}
    else
      scope_by_key = Map.new(grants, &{&1.permission, &1.scope})

      Enum.reduce_while(grants, {:ok, grants}, fn grant, {:ok, acc} ->
        case Permission.fetch(grant.permission) do
          {:ok, %{requires_read: nil}} ->
            {:cont, {:ok, acc}}

          {:ok, %{requires_read: required}} ->
            case Map.fetch(scope_by_key, required) do
              {:ok, read_scope}
              when read_scope == grant.scope or
                     (required == "tenant_services.read" and read_scope == :all_tenants and
                        grant.scope == :assigned_tenants) ->
                {:cont, {:ok, acc}}

              _ ->
                {:halt, {:error, {:missing_prerequisite, required}}}
            end

          error ->
            {:halt, error}
        end
      end)
    end
  end

  defp insert_role(attrs, grants) do
    changeset =
      IdentityRole.ordinary_changeset(%IdentityRole{}, %{
        public_id: Map.get(attrs, :public_id, Map.get(attrs, "public_id")),
        slug: Map.get(attrs, :slug, Map.get(attrs, "slug")),
        name: Map.get(attrs, :name, Map.get(attrs, "name"))
      })

    case Repo.insert(changeset) do
      {:ok, role} ->
        rows =
          Enum.map(grants, &%{role_id: role.id, permission_key: &1.permission, scope: &1.scope})

        _ = if rows != [], do: Repo.insert_all(IdentityRolePermission, rows), else: {0, nil}
        {:ok, role}

      {:error, %{errors: errors}} ->
        if Keyword.has_key?(errors, :slug),
          do: {:error, :slug_taken},
          else: {:error, :invalid_role}
    end
  end

  defp persist_role_changes(role, changes, grants) do
    changeset =
      IdentityRole.ordinary_changeset(role, %{
        name: Map.get(changes, :name, Map.get(changes, "name", role.name)),
        revision: role.revision + 1
      })

    case Repo.update(changeset) do
      {:ok, updated} ->
        _ = Repo.delete_all(from(g in IdentityRolePermission, where: g.role_id == ^role.id))

        rows =
          Enum.map(grants, &%{role_id: role.id, permission_key: &1.permission, scope: &1.scope})

        _ = if rows != [], do: Repo.insert_all(IdentityRolePermission, rows), else: {0, nil}
        {:ok, updated}

      {:error, _} ->
        {:error, :invalid_role}
    end
  end

  defp revoke_role_sessions(role_id, now) do
    Repo.update_all(
      from(s in IdentitySession,
        join: u in assoc(s, :user),
        where: u.role_id == ^role_id and is_nil(s.revoked_at)
      ),
      set: [revoked_at: now]
    )
  end

  defp maybe_clear_obsolete_memberships(role_id, grants) do
    assigned? = Enum.any?(grants, &(&1.scope == "assigned_tenants"))

    unless assigned? do
      Repo.delete_all(
        from(m in IdentityMembership, join: u in assoc(m, :user), where: u.role_id == ^role_id)
      )
    end

    :ok
  end
end
