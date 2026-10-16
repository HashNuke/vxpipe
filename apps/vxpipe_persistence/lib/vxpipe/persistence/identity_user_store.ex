defmodule Vxpipe.Persistence.IdentityUserStore do
  @moduledoc "Ecto adapter for the `Vxpipe.Identity.Ports.Users` boundary."

  @behaviour Vxpipe.Identity.Ports.Users

  import Ecto.Query

  alias Vxpipe.Persistence.{IdentityAccountActor, IdentityRecord}
  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.Schema.{AuthenticationInstallation, IdentityUser}

  @impl true
  def fetch_by_email(normalized_email) do
    query =
      from(u in IdentityUser,
        join: r in assoc(u, :role),
        where: u.normalized_email == ^normalized_email,
        preload: [role: r]
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      user -> {:ok, IdentityRecord.user_port_map(user, IdentityRecord.load_memberships(user.id))}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def fetch_by_public_id(public_id) do
    query =
      from(u in IdentityUser,
        join: r in assoc(u, :role),
        where: u.public_id == ^public_id,
        preload: [role: r]
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      user -> {:ok, IdentityRecord.user_port_map(user, IdentityRecord.load_memberships(user.id))}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def create(attrs) do
    Repo.transaction(fn ->
      with {:ok, role} <-
             IdentityRecord.fetch_role_by_public_id(
               Map.get(attrs, :role_public_id, Map.get(attrs, "role_public_id"))
             ),
           :ok <- revalidate_creator(attrs, role),
           {:ok, user} <- insert_user(attrs, role.id),
           :ok <-
             IdentityRecord.replace_memberships(
               user.id,
               Map.get(attrs, :memberships, Map.get(attrs, "memberships", %{}))
             ),
           :ok <-
             IdentityAccountActor.insert_audit(attrs) do
        IdentityRecord.user_port_map(
          Repo.preload(user, :role),
          IdentityRecord.load_memberships(user.id)
        )
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def apply_update(public_id, changes) do
    Repo.transaction(fn ->
      with {:ok, _installation} <- lock_installation(),
           {:ok, user} <- lock_user_by_public_id(public_id),
           :ok <- check_expected_role(user, changes),
           :ok <- check_expected_password_hash(user, changes),
           {:ok, requested_role} <- maybe_fetch_role(changes),
           :ok <- revalidate_updater(changes, user, requested_role),
           :ok <- check_last_superadmin(user, changes, requested_role),
           {:ok, updated} <- persist_user_changes(user, changes, requested_role),
           :ok <- maybe_replace_memberships(user.id, changes),
           :ok <- maybe_revoke_user_sessions(user.id, changes),
           :ok <-
             IdentityAccountActor.insert_audit(changes) do
        IdentityRecord.user_port_map(
          Repo.preload(updated, :role),
          IdentityRecord.load_memberships(user.id)
        )
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def list(filters) do
    page = Map.get(filters, :page, Map.get(filters, "page", 1))
    page_size = Map.get(filters, :page_size, Map.get(filters, "page_size", 25))
    search = Map.get(filters, :search, Map.get(filters, "search"))
    role_filter = Map.get(filters, :role_public_id, Map.get(filters, "role_public_id"))

    with {:ok, page} <- validate_page(page),
         {:ok, page_size} <- validate_page_size(page_size),
         {:ok, role_id} <- resolve_role_filter(role_filter) do
      base = from(u in IdentityUser, join: r in assoc(u, :role), preload: [role: r])
      base = if role_id, do: where(base, [u], u.role_id == ^role_id), else: base

      base =
        if is_binary(search) and String.trim(search) != "" do
          pattern = "%#{String.trim(search) |> String.downcase()}%"
          where(base, [u], fragment("lower(?) LIKE ?", u.email, ^pattern))
        else
          base
        end

      total = Repo.aggregate(base, :count)

      users =
        base
        |> order_by([u], asc: u.normalized_email, asc: u.public_id)
        |> limit(^page_size)
        |> offset(^((page - 1) * page_size))
        |> Repo.all()
        |> Enum.map(fn user ->
          user
          |> IdentityRecord.user_port_map(IdentityRecord.load_memberships(user.id))
          |> Map.drop([:password_hash])
        end)

      {:ok, %{users: users, total: total}}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def count_enabled_superadmins do
    count =
      Repo.aggregate(
        from(u in IdentityUser,
          join: r in assoc(u, :role),
          where: r.kind == "superadmin" and is_nil(u.disabled_at)
        ),
        :count
      )

    {:ok, count}
  rescue
    _ -> {:error, :unavailable}
  end

  defp lock_installation do
    case Repo.get(AuthenticationInstallation, "default", lock: "FOR UPDATE") do
      nil -> {:error, :missing}
      installation -> {:ok, installation}
    end
  end

  defp revalidate_creator(attrs, target_role) do
    target_kind = IdentityRecord.role_kind(target_role.kind)
    required = Vxpipe.Identity.Permission.account_kind_permission(target_kind)
    IdentityAccountActor.revalidate(attrs, [required], :create)
  end

  defp revalidate_updater(changes, current_user, requested_role) do
    if self_service_password_proof?(changes) do
      :ok
    else
      current_kind = IdentityRecord.role_kind(current_user.role.kind)

      requested_kind =
        if requested_role do
          IdentityRecord.role_kind(requested_role.kind)
        else
          current_kind
        end

      required =
        [
          Vxpipe.Identity.Permission.account_kind_permission(current_kind),
          Vxpipe.Identity.Permission.account_kind_permission(requested_kind)
        ]
        |> Enum.uniq()

      IdentityAccountActor.revalidate(changes, required, :update)
    end
  end

  # Self-service credential/email changes prove ownership by presenting the
  # current password hash already verified at the domain boundary. They carry
  # `expected_current_password_hash` and touch only email/password fields, so
  # they do not require a privileged actor session. Any role, status, or
  # membership change stays on the privileged path and requires a live actor.
  defp self_service_password_proof?(changes) when is_map(changes) do
    has_proof? =
      is_binary(Map.get(changes, :expected_current_password_hash)) or
        is_binary(Map.get(changes, "expected_current_password_hash"))

    privileged? =
      Map.has_key?(changes, :role_public_id) or Map.has_key?(changes, "role_public_id") or
        Map.has_key?(changes, :memberships) or Map.has_key?(changes, "memberships") or
        Map.has_key?(changes, :disabled) or Map.has_key?(changes, "disabled") or
        Map.has_key?(changes, :disabled_at) or Map.has_key?(changes, "disabled_at") or
        Map.has_key?(changes, :expected_current_role_public_id) or
        Map.has_key?(changes, "expected_current_role_public_id") or
        Map.has_key?(changes, :actor_user_public_id) or
        Map.has_key?(changes, "actor_user_public_id") or
        Map.has_key?(changes, :actor_api_key_public_id) or
        Map.has_key?(changes, "actor_api_key_public_id")

    has_proof? and not privileged?
  end

  defp insert_user(attrs, role_id) do
    changeset =
      IdentityUser.changeset(%IdentityUser{}, %{
        public_id: Map.get(attrs, :public_id, Map.get(attrs, "public_id")),
        email: Map.get(attrs, :email, Map.get(attrs, "email")),
        normalized_email: Map.get(attrs, :normalized_email, Map.get(attrs, "normalized_email")),
        password_hash: Map.get(attrs, :password_hash, Map.get(attrs, "password_hash")),
        role_id: role_id
      })

    case Repo.insert(changeset) do
      {:ok, user} ->
        {:ok, user}

      {:error, %{errors: errors}} ->
        if Keyword.has_key?(errors, :normalized_email),
          do: {:error, :email_taken},
          else: {:error, :invalid_user}
    end
  end

  defp lock_user_by_public_id(public_id) do
    case Repo.one(
           from(u in IdentityUser,
             where: u.public_id == ^public_id,
             lock: "FOR UPDATE",
             preload: [:role]
           )
         ) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp check_expected_role(user, changes) do
    expected =
      Map.get(
        changes,
        :expected_current_role_public_id,
        Map.get(changes, "expected_current_role_public_id")
      )

    requesting_role_change? =
      Map.has_key?(changes, :role_public_id) or Map.has_key?(changes, "role_public_id")

    cond do
      is_binary(expected) ->
        if user.role.public_id == expected, do: :ok, else: {:error, :stale_target}

      requesting_role_change? ->
        {:error, :stale_target}

      is_nil(expected) ->
        :ok

      true ->
        {:error, :stale_target}
    end
  end

  defp check_expected_password_hash(user, changes) do
    case Map.get(
           changes,
           :expected_current_password_hash,
           Map.get(changes, "expected_current_password_hash")
         ) do
      nil ->
        :ok

      expected when is_binary(expected) ->
        if user.password_hash == expected, do: :ok, else: {:error, :stale_target}

      _ ->
        {:error, :stale_target}
    end
  end

  defp maybe_fetch_role(changes) do
    case Map.get(changes, :role_public_id, Map.get(changes, "role_public_id")) do
      nil -> {:ok, nil}
      public_id -> IdentityRecord.fetch_role_by_public_id(public_id)
    end
  end

  defp check_last_superadmin(user, changes, requested_role) do
    current_superadmin? = user.role.kind == "superadmin" and is_nil(user.disabled_at)

    will_disable? =
      Map.get(changes, :disabled, Map.get(changes, "disabled", false)) == true or
        not is_nil(Map.get(changes, :disabled_at))

    will_leave_superadmin? = requested_role != nil and requested_role.kind != "superadmin"

    if current_superadmin? and (will_disable? or will_leave_superadmin?) do
      other_ids =
        Repo.all(
          from(u in IdentityUser,
            join: r in assoc(u, :role),
            where: r.kind == "superadmin" and is_nil(u.disabled_at) and u.id != ^user.id,
            select: u.id,
            lock: "FOR UPDATE"
          )
        )

      if other_ids == [], do: {:error, :last_superadmin}, else: :ok
    else
      :ok
    end
  end

  defp persist_user_changes(user, changes, requested_role) do
    attrs = %{}

    attrs =
      case Map.get(changes, :email, Map.get(changes, "email")) do
        nil ->
          attrs

        email ->
          Map.merge(attrs, %{
            email: String.trim(email),
            normalized_email: email |> String.trim() |> String.downcase()
          })
      end

    attrs =
      case Map.get(changes, :password_hash, Map.get(changes, "password_hash")) do
        nil -> attrs
        hash -> Map.put(attrs, :password_hash, hash)
      end

    attrs = if requested_role, do: Map.put(attrs, :role_id, requested_role.id), else: attrs

    attrs =
      cond do
        Map.get(changes, :disabled, Map.get(changes, "disabled")) == true ->
          Map.put(attrs, :disabled_at, IdentityRecord.utc_now())

        Map.get(changes, :disabled, Map.get(changes, "disabled")) == false ->
          Map.put(attrs, :disabled_at, nil)

        not is_nil(Map.get(changes, :disabled_at)) ->
          Map.put(attrs, :disabled_at, Map.get(changes, :disabled_at))

        true ->
          attrs
      end

    # The user row is locked by apply_update/2. Advance the durable delegation
    # version in the same update and transaction as the authority change.
    attrs =
      if invalidates_authorization?(changes),
        do: Map.put(attrs, :authorization_version, user.authorization_version + 1),
        else: attrs

    case Repo.update(IdentityUser.changeset(user, attrs)) do
      {:ok, updated} ->
        {:ok, updated}

      {:error, %{errors: errors}} ->
        if Keyword.has_key?(errors, :normalized_email),
          do: {:error, :email_taken},
          else: {:error, :invalid_user}
    end
  end

  defp maybe_replace_memberships(user_id, changes) do
    cond do
      Map.has_key?(changes, :memberships) ->
        IdentityRecord.replace_memberships(user_id, Map.get(changes, :memberships))

      Map.has_key?(changes, "memberships") ->
        IdentityRecord.replace_memberships(user_id, Map.get(changes, "memberships"))

      true ->
        :ok
    end
  end

  # Session revocation commits in the same transaction as the account mutation,
  # so a committed role/membership/status/password change can never leave live
  # sessions behind. Revocation is idempotent; the domain layer may repeat it.
  defp maybe_revoke_user_sessions(user_id, changes) do
    if invalidates_authorization?(changes) do
      now = IdentityRecord.utc_now()

      _ =
        Repo.update_all(
          from(s in Vxpipe.Persistence.Schema.IdentitySession,
            where: s.user_id == ^user_id and is_nil(s.revoked_at)
          ),
          set: [revoked_at: now]
        )

      :ok
    else
      :ok
    end
  end

  defp invalidates_authorization?(changes) do
    Map.has_key?(changes, :role_public_id) or Map.has_key?(changes, "role_public_id") or
      Map.has_key?(changes, :memberships) or Map.has_key?(changes, "memberships") or
      Map.has_key?(changes, :disabled_at) or
      Map.get(changes, :disabled, Map.get(changes, "disabled")) != nil or
      Map.has_key?(changes, :password_hash) or Map.has_key?(changes, "password_hash")
  end

  defp validate_page(page) when is_integer(page) and page >= 1, do: {:ok, page}
  defp validate_page(_), do: {:error, :invalid_pagination}

  defp validate_page_size(size) when is_integer(size) and size >= 1 and size <= 100,
    do: {:ok, size}

  defp validate_page_size(_), do: {:error, :invalid_pagination}

  defp resolve_role_filter(nil), do: {:ok, nil}

  defp resolve_role_filter(public_id) when is_binary(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} -> lookup_role_id(public_id)
      :error -> {:error, :invalid_role_filter}
    end
  end

  defp resolve_role_filter(_), do: {:error, :invalid_role_filter}

  defp lookup_role_id(public_id) do
    alias Vxpipe.Persistence.Schema.IdentityRole

    case Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id, select: r.id)) do
      nil -> {:error, :invalid_role_filter}
      id -> {:ok, id}
    end
  end
end
