defmodule Vxpipe.Identity.Roles do
  @moduledoc "Ordinary role CRUD. Built-ins are immutable; reserved grants rejected."

  alias Vxpipe.Identity.Permission

  @protected_kinds [:superadmin, :admin]

  @spec list_roles(map(), map()) :: {:ok, [map()]} | {:error, term()}
  def list_roles(deps, actor) do
    with :ok <- authorize_read(actor), do: deps.roles.list()
  end

  @doc "Returns one bounded full-role page for a named administrator."
  def list_roles(deps, actor, filters) do
    with :ok <- authorize_read(actor),
         {:ok, filters} <- role_options_page(filters),
         {:ok, result} <- deps.roles.list_page(filters) do
      Vxpipe.Identity.AccountPage.result(result, filters)
    end
  end

  def get_role(deps, actor, id) do
    with :ok <- authorize_read(actor), do: deps.roles.fetch(id)
  end

  def affected_user_count(deps, actor, id) do
    with :ok <- authorize_read(actor), do: deps.roles.count_users(id)
  end

  defp authorize_read(actor) do
    with :ok <- Vxpipe.Identity.Authorization.require_actor_identity(actor),
         :ok <- require_builtin(actor),
         do: :ok
  end

  @spec list_role_options(map(), map()) :: {:ok, [map()]} | {:error, term()}
  def list_role_options(deps, actor) do
    roles = Map.fetch!(deps, :roles)

    if MapSet.member?(actor.grants, "users.read") or actor.account_kind in @protected_kinds do
      case roles.list() do
        {:ok, list} -> {:ok, Enum.map(list, &Map.take(&1, [:public_id, :name, :slug, :kind]))}
        error -> error
      end
    else
      {:error, :forbidden}
    end
  end

  @doc "Bounded safe role options for the canonical account API."
  def list_role_options(deps, actor, filters) do
    with :ok <- Vxpipe.Identity.AccountAuthority.require_read(actor),
         {:ok, filters} <- role_options_page(filters),
         {:ok, result} <- deps.roles.list_options(filters) do
      Vxpipe.Identity.AccountPage.result(result, filters)
    end
  end

  defp role_options_page(filters) when is_map(filters) do
    if Enum.all?(Map.keys(filters), &(&1 in [:page, :page_size])),
      do: Vxpipe.Identity.AccountPage.filters(filters),
      else: {:error, :invalid_pagination}
  end

  defp role_options_page(_filters), do: {:error, :invalid_pagination}

  @spec create_role(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def create_role(deps, actor, attrs) do
    roles = Map.fetch!(deps, :roles)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)
    uuid = Map.get(deps, :uuid, Vxpipe.Identity.Uuid)

    with :ok <- Vxpipe.Identity.Authorization.require_actor_identity(actor),
         :ok <- require_builtin(actor),
         {:ok, validated} <- validate_definition(attrs, nil) do
      public_id = uuid.generate()

      roles.create(%{
        public_id: public_id,
        slug: validated.slug,
        name: validated.name,
        grants: validated.grants,
        audit_event: %{
          action: "role_created",
          actor_user_public_id: actor.user_public_id,
          target_role_public_id: public_id,
          summary: %{}
        },
        audit: audit,
        actor_user_public_id: actor.user_public_id,
        actor_session_public_id: actor_session_id(actor)
      })
    end
  end

  @spec update_role(map(), map(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_role(deps, actor, role_public_id, changes) do
    roles = Map.fetch!(deps, :roles)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)

    with :ok <- Vxpipe.Identity.Authorization.require_actor_identity(actor),
         :ok <- require_builtin(actor),
         :ok <- require_expected_revision(changes),
         {:ok, current} <- roles.fetch(role_public_id),
         :ok <- require_ordinary(current),
         {:ok, validated} <- validate_definition(changes, current) do
      roles.apply_update(role_public_id, %{
        name: validated.name,
        grants: validated.grants,
        expected_revision:
          Map.get(changes, :expected_revision, Map.get(changes, "expected_revision")),
        audit_event: %{
          action: "role_updated",
          actor_user_public_id: actor.user_public_id,
          target_role_public_id: role_public_id,
          summary: %{}
        },
        audit: audit,
        actor_user_public_id: actor.user_public_id,
        actor_session_public_id: actor_session_id(actor)
      })
    end
  end

  @spec delete_role(map(), map(), String.t()) :: :ok | {:error, term()}
  def delete_role(deps, actor, role_public_id) do
    roles = Map.fetch!(deps, :roles)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)

    with :ok <- Vxpipe.Identity.Authorization.require_actor_identity(actor),
         :ok <- require_builtin(actor),
         {:ok, current} <- roles.fetch(role_public_id),
         :ok <- require_ordinary(current) do
      # Stores that support atomic audit accept opts; fakes ignore extra args via fallback.
      try_delete(roles, role_public_id, %{
        audit_event: %{
          action: "role_deleted",
          actor_user_public_id: actor.user_public_id,
          target_role_public_id: role_public_id,
          summary: %{}
        },
        audit: audit,
        actor_user_public_id: actor.user_public_id,
        actor_session_public_id: actor_session_id(actor)
      })
    end
  end

  defp try_delete(roles, public_id, opts) do
    if function_exported?(roles, :delete, 2) do
      roles.delete(public_id, opts)
    else
      with :ok <- roles.delete(public_id),
           {:ok, audit} <- Map.fetch(opts, :audit),
           event = Map.delete(opts, :audit),
           :ok <- audit.append(Map.delete(event, :audit)) do
        :ok
      else
        :error -> {:error, :unavailable}
        error -> error
      end
    end
  end

  defp require_builtin(%{account_kind: kind}) when kind in [:superadmin, :admin], do: :ok
  defp require_builtin(_), do: {:error, :forbidden}

  defp require_expected_revision(changes) do
    case Map.get(changes, :expected_revision, Map.get(changes, "expected_revision")) do
      revision when is_integer(revision) and revision >= 1 -> :ok
      _ -> {:error, :stale_revision}
    end
  end

  defp require_ordinary(%{kind: kind}) when kind in [:member, nil], do: :ok
  defp require_ordinary(%{"kind" => kind}) when kind in [nil, "member"], do: :ok
  defp require_ordinary(%{kind: _}), do: {:error, :protected_role}
  defp require_ordinary(_), do: :ok

  defp validate_definition(attrs, current) do
    name = Map.get(attrs, :name, Map.get(attrs, "name", current && current[:name]))
    slug = Map.get(attrs, :slug, Map.get(attrs, "slug", current && current[:slug]))
    grants = Map.get(attrs, :grants, Map.get(attrs, "grants", current && current[:grants]))

    with :ok <- validate_name(name),
         :ok <- validate_slug(slug),
         {:ok, grants} <- validate_grants(grants) do
      {:ok, %{name: name, slug: slug, grants: grants}}
    end
  end

  defp validate_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if byte_size(trimmed) in 1..128, do: :ok, else: {:error, :invalid_role_name}
  end

  defp validate_name(_), do: {:error, :invalid_role_name}

  defp validate_slug(slug) when is_binary(slug) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9_-]{1,62}\z/, slug),
      do: :ok,
      else: {:error, :invalid_role_slug}
  end

  defp validate_slug(_), do: {:error, :invalid_role_slug}

  defp validate_grants(grants) when is_list(grants) do
    Enum.reduce_while(grants, {:ok, []}, fn grant, {:ok, acc} ->
      case validate_grant(grant) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> check_grant_dependencies(Enum.reverse(list))
      error -> error
    end
  end

  defp validate_grants(_), do: {:error, :invalid_grants}

  defp validate_grant(%{permission: permission, scope: scope}),
    do: validate_grant_pair(permission, scope)

  defp validate_grant(%{"permission" => permission, "scope" => scope}),
    do: validate_grant_pair(permission, scope)

  defp validate_grant(_), do: {:error, :invalid_grant}

  defp validate_grant_pair(permission, scope) do
    with {:ok, scope_atom} <- normalize_scope(scope),
         {:ok, entry} <- Permission.fetch(permission),
         true <- scope_atom in entry.scopes do
      if Permission.reserved?(permission) do
        {:error, :reserved_permission}
      else
        {:ok, %{permission: permission, scope: scope_atom}}
      end
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_scope}
      _ -> {:error, :invalid_grant}
    end
  end

  defp normalize_scope(:installation), do: {:ok, :installation}
  defp normalize_scope(:all_tenants), do: {:ok, :all_tenants}
  defp normalize_scope(:assigned_tenants), do: {:ok, :assigned_tenants}
  defp normalize_scope("installation"), do: {:ok, :installation}
  defp normalize_scope("all_tenants"), do: {:ok, :all_tenants}
  defp normalize_scope("assigned_tenants"), do: {:ok, :assigned_tenants}
  defp normalize_scope(_), do: {:error, :invalid_scope}

  defp check_grant_dependencies(grants) do
    with {:ok, grants} <- check_duplicate_keys(grants) do
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

  defp check_duplicate_keys(grants) do
    keys = Enum.map(grants, & &1.permission)

    if length(keys) == length(Enum.uniq(keys)) do
      {:ok, grants}
    else
      {:error, :overlapping_scopes}
    end
  end

  defp actor_session_id(%{session_public_id: id}) when is_binary(id), do: id
  defp actor_session_id(%{"session_public_id" => id}) when is_binary(id), do: id
  defp actor_session_id(_), do: nil
end
