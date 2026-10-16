defmodule Vxpipe.Identity.Accounts do
  @moduledoc "Account administration bounded by the exact category matrix."

  alias Vxpipe.Identity.{AccountAuthority, AccountPage, Authorization, Email, Password}

  @spec create_user(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def create_user(deps, actor, attrs) do
    users = Map.fetch!(deps, :users)
    roles = Map.fetch!(deps, :roles)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)
    hasher = Map.fetch!(deps, :hasher)
    uuid = Map.get(deps, :uuid, Vxpipe.Identity.Uuid)

    with :ok <- AccountAuthority.require_identity(actor),
         {:ok, normalized} <- Email.normalize(Map.get(attrs, :email, Map.get(attrs, "email"))),
         :ok <-
           Password.confirm(Map.get(attrs, :password), Map.get(attrs, :password_confirmation)),
         {:ok, role} <-
           roles.fetch(Map.get(attrs, :role_public_id, Map.get(attrs, "role_public_id"))),
         target_kind = role_kind(role),
         :ok <- Authorization.require_account_create(AccountAuthority.grants(actor), target_kind),
         :ok <- validate_memberships(role, Map.get(attrs, :memberships, %{})),
         {:ok, hash} <- hasher.hash(Map.get(attrs, :password)) do
      public_id = uuid.generate()

      audit_event =
        %{
          action: "user_created",
          target_user_public_id: public_id,
          summary: %{role: role.public_id}
        }
        |> Map.merge(Map.delete(AccountAuthority.attribution(actor), :actor_session_public_id))

      with {:ok, user} <-
             users.create(
               Map.merge(
                 %{
                   public_id: public_id,
                   email: String.trim(Map.get(attrs, :email, Map.get(attrs, "email"))),
                   normalized_email: normalized,
                   password_hash: hash,
                   role_public_id: role.public_id,
                   memberships: Map.get(attrs, :memberships, %{}),
                   audit_event: audit_event,
                   audit: audit
                 },
                 AccountAuthority.attribution(actor)
               )
             ) do
        {:ok, sanitize(user)}
      end
    end
  end

  @spec update_user(map(), map(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_user(deps, actor, target_public_id, changes) do
    users = Map.fetch!(deps, :users)
    roles = Map.fetch!(deps, :roles)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)

    with :ok <- AccountAuthority.require_identity(actor),
         :ok <- AccountAuthority.require_update_fields(actor, changes),
         {:ok, current} <- users.fetch_by_public_id(target_public_id),
         :ok <- check_expected_role(current, changes),
         {:ok, {current_kind, requested_kind, requested_role}} <-
           resolve_kinds(roles, current, changes),
         :ok <-
           Authorization.require_account_write(
             AccountAuthority.grants(actor),
             current_kind,
             requested_kind
           ),
         :ok <- validate_update_fields(changes),
         {:ok, membership_role} <- membership_role(roles, current, requested_role),
         :ok <-
           validate_memberships(
             membership_role,
             Map.get(
               changes,
               :memberships,
               Map.get(changes, "memberships", current_memberships(current))
             )
           ),
         {:ok, updated} <-
           apply_user_update(
             users,
             target_public_id,
             current,
             changes,
             Map.merge(
               %{
                 action: "user_updated",
                 target_user_public_id: target_public_id,
                 summary: %{},
                 audit: audit
               },
               AccountAuthority.attribution(actor)
             )
           ) do
      {:ok, sanitize(updated)}
    else
      {:error, :stale_target} -> {:error, :forbidden}
      error -> error
    end
  end

  @spec reset_password(map(), map(), String.t(), String.t(), String.t(), map()) ::
          :ok | {:error, term()}
  def reset_password(deps, actor, target_public_id, new_password, confirmation, opts \\ %{}) do
    users = Map.fetch!(deps, :users)
    audit = Map.get(deps, :audit, Vxpipe.Identity.Accounts.NoopAudit)
    hasher = Map.fetch!(deps, :hasher)

    with :ok <- Authorization.require_actor_identity(actor),
         :ok <- Password.confirm(new_password, confirmation),
         {:ok, target} <- users.fetch_by_public_id(target_public_id),
         :ok <-
           Authorization.require_account_write(
             actor.grants,
             target_kind(target),
             target_kind(target)
           ),
         {:ok, hash} <- hasher.hash(new_password),
         {:ok, _} <-
           apply_user_update(
             users,
             target_public_id,
             target,
             %{
               password_hash: hash,
               expected_current_role_public_id:
                 opts_value(opts, :expected_current_role_public_id, target_role_public_id(target))
             },
             %{
               action: "password_reset",
               actor_user_public_id: actor.user_public_id,
               target_user_public_id: target_public_id,
               summary: %{},
               audit: audit,
               actor_session_public_id: actor_session_id(actor)
             }
           ) do
      :ok
    else
      {:error, :stale_target} -> {:error, :forbidden}
      error -> error
    end
  end

  @spec change_own_password(map(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def change_own_password(deps, user_public_id, current_password, new_password, confirmation) do
    users = Map.fetch!(deps, :users)
    hasher = Map.fetch!(deps, :hasher)

    with :ok <- Password.confirm(new_password, confirmation),
         {:ok, user} <- users.fetch_by_public_id(user_public_id),
         true <-
           hasher.verify(current_password, user.password_hash) || {:error, :invalid_credentials},
         {:ok, hash} <- hasher.hash(new_password),
         {:ok, _} <-
           users.apply_update(user_public_id, %{
             password_hash: hash,
             expected_current_password_hash: user.password_hash
           }) do
      :ok
    else
      {:error, :stale_target} -> {:error, :invalid_credentials}
      error -> error
    end
  end

  @spec change_own_email(map(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def change_own_email(deps, user_public_id, current_password, new_email) do
    users = Map.fetch!(deps, :users)
    hasher = Map.fetch!(deps, :hasher)

    with {:ok, normalized} <- Email.normalize(new_email),
         {:ok, user} <- users.fetch_by_public_id(user_public_id),
         true <-
           hasher.verify(current_password, user.password_hash) || {:error, :invalid_credentials},
         {:ok, updated} <-
           users.apply_update(user_public_id, %{
             email: String.trim(new_email),
             normalized_email: normalized,
             expected_current_password_hash: user.password_hash
           }) do
      {:ok, sanitize(updated)}
    else
      {:error, :stale_target} -> {:error, :invalid_credentials}
      error -> error
    end
  end

  @spec change_own_details(
          map(),
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, map()} | {:error, term()}
  def change_own_details(
        deps,
        user_public_id,
        current_password,
        email,
        new_password,
        confirmation
      ) do
    users = Map.fetch!(deps, :users)
    hasher = Map.fetch!(deps, :hasher)

    with :ok <- require_detail_change(email, new_password),
         {:ok, normalized} <- maybe_normalize_email(email),
         :ok <- maybe_confirm_password(new_password, confirmation),
         {:ok, user} <- users.fetch_by_public_id(user_public_id),
         true <-
           hasher.verify(current_password, user.password_hash) || {:error, :invalid_credentials},
         {:ok, password_hash} <- maybe_hash_password(hasher, new_password),
         {:ok, updated} <-
           users.apply_update(
             user_public_id,
             detail_changes(email, normalized, password_hash, user)
           ) do
      {:ok, sanitize(updated)}
    else
      {:error, :stale_target} -> {:error, :invalid_credentials}
      error -> error
    end
  end

  @spec list_users(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def list_users(deps, actor, filters) do
    users = Map.fetch!(deps, :users)

    with :ok <- AccountAuthority.require_read(actor),
         {:ok, filters} <- AccountPage.filters(filters),
         {:ok, result} <- users.list(filters) do
      AccountPage.result(result, filters)
    end
  end

  @spec get_user(map(), map(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_user(deps, actor, target_public_id) do
    users = Map.fetch!(deps, :users)

    if AccountAuthority.require_read(actor) == :ok do
      case users.fetch_by_public_id(target_public_id) do
        {:ok, user} -> {:ok, sanitize(user)}
        error -> error
      end
    else
      {:error, :forbidden}
    end
  end

  defp require_detail_change(nil, nil), do: {:error, :no_changes}
  defp require_detail_change(_, _), do: :ok

  defp maybe_normalize_email(nil), do: {:ok, nil}
  defp maybe_normalize_email(email), do: Email.normalize(email)

  defp maybe_confirm_password(nil, _confirmation), do: :ok

  defp maybe_confirm_password(new_password, confirmation),
    do: Password.confirm(new_password, confirmation)

  defp maybe_hash_password(_hasher, nil), do: {:ok, nil}
  defp maybe_hash_password(hasher, new_password), do: hasher.hash(new_password)

  defp detail_changes(email, normalized, password_hash, user) do
    changes = %{expected_current_password_hash: user.password_hash}

    changes =
      if is_binary(email),
        do: Map.merge(changes, %{email: String.trim(email), normalized_email: normalized}),
        else: changes

    if is_binary(password_hash),
      do: Map.put(changes, :password_hash, password_hash),
      else: changes
  end

  defp role_kind(%{kind: kind}) when kind in [:member, :admin, :superadmin], do: kind
  defp role_kind(%{role_kind: kind}) when kind in [:member, :admin, :superadmin], do: kind
  defp role_kind(_), do: :member

  defp target_kind(%{role_kind: kind}) when kind in [:member, :admin, :superadmin], do: kind
  defp target_kind(%{kind: kind}) when kind in [:member, :admin, :superadmin], do: kind
  defp target_kind(_), do: :member

  defp membership_role(_roles, _current, requested_role) when is_map(requested_role) do
    {:ok, requested_role}
  end

  defp membership_role(roles, current, nil) do
    case target_role_public_id(current) do
      nil ->
        {:error, :forbidden}

      role_public_id ->
        case roles.fetch(role_public_id) do
          {:ok, role} -> {:ok, role}
          error -> error
        end
    end
  end

  # Fail-fast stale-edit check at the domain boundary; the persistence
  # adapter rechecks against the locked row for race safety.
  defp check_expected_role(current, changes) do
    case Map.get(
           changes,
           :expected_current_role_public_id,
           Map.get(changes, "expected_current_role_public_id")
         ) do
      nil ->
        :ok

      expected when is_binary(expected) ->
        if target_role_public_id(current) == expected, do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  # Rejects concurrent role changes inside the locked persistence transaction.
  # Callers pass the role observed during the precheck; the adapter compares it
  # against the row locked `FOR UPDATE` and returns `:stale_target` on drift,
  # which account workflows map to `:forbidden`.
  # Audit is carried in the same atomic store transaction via `:audit_event`.
  # Fail closed when the current target role is missing.
  defp apply_user_update(users, target_public_id, current, changes, audit_info) do
    case target_role_public_id(current) do
      nil ->
        {:error, :forbidden}

      current_role_id ->
        attribution =
          Map.take(audit_info, [
            :actor_user_public_id,
            :actor_session_public_id,
            :actor_api_key_public_id,
            :actor_oauth_grant_public_id
          ])

        event = Map.drop(audit_info, [:audit, :actor_session_public_id])

        stamped =
          changes
          |> AccountAuthority.stamp(attribution)
          |> Map.put_new(:expected_current_role_public_id, current_role_id)
          |> Map.put(:audit_event, event)
          |> Map.put(:audit, Map.get(audit_info, :audit, Vxpipe.Identity.Accounts.NoopAudit))

        case users.apply_update(target_public_id, stamped) do
          {:ok, updated} -> {:ok, updated}
          error -> error
        end
    end
  end

  defp actor_session_id(%{session_public_id: id}) when is_binary(id), do: id
  defp actor_session_id(%{"session_public_id" => id}) when is_binary(id), do: id
  defp actor_session_id(_), do: nil

  defp target_role_public_id(%{role_public_id: id}) when is_binary(id), do: id
  defp target_role_public_id(%{"role_public_id" => id}) when is_binary(id), do: id
  defp target_role_public_id(_), do: nil

  defp opts_value(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)
  defp opts_value(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp opts_value(_opts, _key, default), do: default

  defp resolve_kinds(roles, current, changes) do
    current_kind = target_kind(current)
    role_id = Map.get(changes, :role_public_id, Map.get(changes, "role_public_id"))

    if is_nil(role_id) do
      {:ok, {current_kind, current_kind, nil}}
    else
      case roles.fetch(role_id) do
        {:ok, role} -> {:ok, {current_kind, role_kind(role), role}}
        error -> error
      end
    end
  end

  defp validate_update_fields(changes) when is_map(changes) do
    changes =
      Map.take(changes, [
        :email,
        "email",
        :role_public_id,
        :memberships,
        :disabled_at,
        :disabled,
        :password_hash
      ])

    case Map.get(changes, :email, Map.get(changes, "email")) do
      nil ->
        :ok

      email ->
        case Email.normalize(email) do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  defp validate_memberships(_role, memberships) when map_size(memberships) == 0, do: :ok

  defp validate_memberships(role, memberships) when is_map(memberships) do
    grants = Map.get(role, :grants, [])

    assigned? =
      Enum.any?(grants, fn
        %{scope: :assigned_tenants} -> true
        %{"scope" => "assigned_tenants"} -> true
        _ -> false
      end)

    cond do
      map_size(memberships) == 0 -> :ok
      assigned? -> validate_levels(memberships)
      true -> {:error, :memberships_not_allowed}
    end
  end

  defp validate_memberships(_role, _memberships), do: {:error, :invalid_memberships}

  defp validate_levels(memberships) do
    if Enum.all?(memberships, fn {_k, v} -> v in [:read, :read_write, "read", "read_write"] end) do
      :ok
    else
      {:error, :invalid_memberships}
    end
  end

  defp current_memberships(%{memberships: m}) when is_map(m), do: m
  defp current_memberships(_), do: %{}

  defp sanitize(user) when is_map(user), do: Map.drop(user, [:password_hash, "password_hash"])
end
