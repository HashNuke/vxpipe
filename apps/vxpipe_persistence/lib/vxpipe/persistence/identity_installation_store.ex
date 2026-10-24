defmodule Vxpipe.Persistence.IdentityInstallationStore do
  @moduledoc """
  Ecto adapter for the typed authentication singleton, distinct from demo setup.

  First-run creation and proof-bound upgrade creation each run atomically:
  singleton lock, pending check, Superadmin insert, completion marker plus
  initial-Superadmin reference, and session insert.
  """

  @behaviour Vxpipe.Identity.Ports.Installations

  import Ecto.Query

  alias Vxpipe.Persistence.IdentityAuditStore
  alias Vxpipe.Persistence.IdentityRecord
  alias Vxpipe.Persistence.Repo

  alias Vxpipe.Persistence.Schema.{
    AuthenticationInstallation,
    AuthenticationSetupProof,
    IdentityRole,
    IdentitySession,
    IdentityUser
  }

  @impl true
  def fetch do
    case Repo.get(AuthenticationInstallation, "default") do
      nil ->
        {:error, :missing}

      %AuthenticationInstallation{bootstrap_mode: mode} = row
      when mode in ["first_run", "operator_required"] ->
        {:ok,
         %{
           mode: bootstrap_mode(mode),
           setup_completed_at: row.setup_completed_at,
           public_url: row.public_url,
           public_url_revision: row.public_url_revision,
           initial_superadmin_public_id: initial_superadmin_public_id(row)
         }}

      _ ->
        {:error, :corrupt}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def update_public_url(actor, url, revision) do
    Repo.transaction(fn ->
      with :ok <- Vxpipe.Identity.InstallationSettings.authorize(actor),
           :ok <-
             IdentityRecord.revalidate_actor(
               Vxpipe.Identity.AccountAuthority.attribution(actor),
               ["users.superadmins.write"]
             ),
           {:ok, ^url} <- Vxpipe.Identity.InstallationURL.normalize(url),
           {:ok, installation} <- lock_installation(),
           :ok <- require_complete(installation),
           true <- installation.public_url_revision == revision,
           {:ok, updated} <- change_public_url(installation, actor, url) do
        %{public_url: updated.public_url, revision: updated.public_url_revision}
      else
        false -> Repo.rollback(:conflict)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  rescue
    _ -> {:error, :unavailable}
  end

  defp change_public_url(%{public_url: url} = installation, _actor, url), do: {:ok, installation}

  defp change_public_url(installation, actor, url) do
    with {:ok, updated} <-
           installation
           |> AuthenticationInstallation.changeset(%{
             public_url: url,
             public_url_revision: installation.public_url_revision + 1
           })
           |> Repo.update(),
         :ok <-
           IdentityAuditStore.append(%{
             action: "installation_url_updated",
             actor_user_public_id: actor.user_public_id,
             summary: %{revision: updated.public_url_revision}
           }) do
      {:ok, updated}
    end
  end

  @impl true
  def complete_first_run(attrs) do
    Repo.transaction(fn ->
      with {:ok, installation} <- lock_installation(),
           :ok <- require_pending(installation, :first_run),
           {:ok, result} <- insert_initial_superadmin(installation, attrs) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def consume_setup_proof(proof, attrs) do
    Repo.transaction(fn ->
      with {:ok, installation} <- lock_installation(),
           :ok <- require_pending(installation, :operator_required),
           {:ok, _} <- lock_and_burn_proof(proof, "setup"),
           {:ok, result} <- insert_initial_superadmin(installation, attrs) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def issue_setup_proof(ttl_seconds) do
    Repo.transaction(fn ->
      with {:ok, installation} <- lock_installation(),
           :ok <- require_pending_setup_proof(installation) do
        proof = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        digest = :crypto.hash(:sha256, proof) |> Base.encode16(case: :lower)
        now = IdentityRecord.utc_now()

        changeset =
          AuthenticationSetupProof.changeset(%AuthenticationSetupProof{}, %{
            proof_digest: digest,
            purpose: "setup",
            expires_at: DateTime.add(now, ttl_seconds, :second)
          })

        case Repo.insert(changeset) do
          {:ok, _} -> %{proof: proof}
          {:error, _} -> Repo.rollback(:unavailable)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def issue_recovery_proof(ttl_seconds) do
    Repo.transaction(fn ->
      with {:ok, installation} <- lock_installation(),
           :ok <- require_complete(installation) do
        proof = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        digest = :crypto.hash(:sha256, proof) |> Base.encode16(case: :lower)
        now = IdentityRecord.utc_now()

        changeset =
          AuthenticationSetupProof.changeset(%AuthenticationSetupProof{}, %{
            proof_digest: digest,
            purpose: "recovery",
            expires_at: DateTime.add(now, ttl_seconds, :second)
          })

        case Repo.insert(changeset) do
          {:ok, _} -> %{proof: proof}
          {:error, _} -> Repo.rollback(:unavailable)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def consume_recovery_proof(proof, attrs) do
    Repo.transaction(fn ->
      with {:ok, installation} <- lock_installation(),
           :ok <- require_complete(installation),
           {:ok, _} <- lock_and_burn_proof(proof, "recovery"),
           {:ok, result} <- recover_superadmin(attrs) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp lock_installation do
    case Repo.one(
           from(i in AuthenticationInstallation, where: i.key == "default", lock: "FOR UPDATE")
         ) do
      nil -> {:error, :missing}
      installation -> {:ok, installation}
    end
  end

  defp require_pending(%AuthenticationInstallation{setup_completed_at: %DateTime{}}, _mode) do
    {:error, :already_completed}
  end

  defp require_pending(%AuthenticationInstallation{bootstrap_mode: "first_run"}, :first_run),
    do: :ok

  defp require_pending(
         %AuthenticationInstallation{bootstrap_mode: "operator_required"},
         :operator_required
       ),
       do: :ok

  defp require_pending(
         %AuthenticationInstallation{bootstrap_mode: "operator_required"},
         :first_run
       ),
       do: {:error, :proof_required}

  defp require_pending(_, _), do: {:error, :corrupt}

  defp require_complete(%AuthenticationInstallation{setup_completed_at: %DateTime{}}), do: :ok
  defp require_complete(_), do: {:error, :not_complete}

  defp require_pending_setup_proof(%AuthenticationInstallation{
         setup_completed_at: %DateTime{}
       }) do
    {:error, :already_completed}
  end

  defp require_pending_setup_proof(%AuthenticationInstallation{
         bootstrap_mode: "operator_required"
       }),
       do: :ok

  defp require_pending_setup_proof(%AuthenticationInstallation{bootstrap_mode: "first_run"}),
    do: {:error, :not_required}

  defp require_pending_setup_proof(_), do: {:error, :corrupt}

  defp recover_superadmin(attrs) do
    normalized = Map.get(attrs, :normalized_email, Map.get(attrs, "normalized_email"))
    password_hash = Map.get(attrs, :password_hash, Map.get(attrs, "password_hash"))

    with {:ok, user} <- lock_superadmin_by_email(normalized),
         {:ok, updated} <- reset_credentials(user, password_hash),
         :ok <- revoke_all_user_sessions(user.id),
         {:ok, _} <- insert_session(user.id, attrs),
         :ok <- append_recovery_audit(attrs, user) do
      {:ok,
       %{
         user: IdentityRecord.user_port_map(Repo.preload(updated, :role), %{}),
         session: %{
           public_id: Map.get(attrs, :session_public_id, Map.get(attrs, "session_public_id"))
         }
       }}
    end
  end

  defp lock_superadmin_by_email(normalized) when is_binary(normalized) do
    case Repo.one(
           from(u in IdentityUser,
             join: r in assoc(u, :role),
             where: u.normalized_email == ^normalized and r.kind == "superadmin",
             lock: "FOR UPDATE",
             preload: [role: r]
           )
         ) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp lock_superadmin_by_email(_), do: {:error, :not_found}

  defp reset_credentials(user, password_hash) when is_binary(password_hash) do
    user
    |> IdentityUser.changeset(%{
      password_hash: password_hash,
      disabled_at: nil,
      authorization_version: user.authorization_version + 1
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp reset_credentials(_, _), do: {:error, :invalid_user}

  defp revoke_all_user_sessions(user_id) do
    now = IdentityRecord.utc_now()

    _ =
      Repo.update_all(
        from(s in IdentitySession, where: s.user_id == ^user_id and is_nil(s.revoked_at)),
        set: [revoked_at: now]
      )

    :ok
  end

  defp insert_initial_superadmin(installation, attrs) do
    with {:ok, role} <- lock_superadmin_role(),
         {:ok, user} <- insert_user(attrs, role.id),
         {:ok, _} <- complete_installation(installation, user.id, Map.get(attrs, :public_url)),
         {:ok, _} <- insert_session(user.id, attrs),
         :ok <- append_setup_audit(attrs, installation, user) do
      {:ok,
       %{
         user: IdentityRecord.user_port_map(Repo.preload(user, :role), %{}),
         session: %{public_id: attrs.session_public_id}
       }}
    else
      {:error, reason} -> {:error, reason}
      error -> error
    end
  end

  defp lock_superadmin_role do
    case Repo.one(from(r in IdentityRole, where: r.kind == "superadmin", lock: "FOR UPDATE")) do
      nil -> {:error, :corrupt}
      role -> {:ok, role}
    end
  end

  defp insert_user(attrs, role_id) do
    changeset =
      IdentityUser.changeset(%IdentityUser{}, %{
        public_id: Map.get(attrs, :user_public_id, Map.get(attrs, "user_public_id")),
        email: Map.get(attrs, :email, Map.get(attrs, "email")),
        normalized_email: Map.get(attrs, :normalized_email, Map.get(attrs, "normalized_email")),
        password_hash: Map.get(attrs, :password_hash, Map.get(attrs, "password_hash")),
        role_id: role_id
      })

    case Repo.insert(changeset) do
      {:ok, user} -> {:ok, user}
      {:error, _} -> {:error, :invalid_user}
    end
  end

  defp complete_installation(installation, user_id, public_url) do
    installation
    |> AuthenticationInstallation.changeset(%{
      setup_completed_at: IdentityRecord.utc_now(),
      initial_superadmin_user_id: user_id,
      public_url: public_url,
      public_url_revision: if(is_nil(public_url), do: 0, else: 1)
    })
    |> Repo.update()
    |> case do
      {:ok, _} -> {:ok, :completed}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp insert_session(user_id, attrs) do
    now = IdentityRecord.utc_now()

    changeset =
      IdentitySession.changeset(%IdentitySession{}, %{
        public_id: attrs.session_public_id,
        user_id: user_id,
        token_digest: attrs.session_digest,
        issued_at: now,
        expires_at: attrs.session_expires_at
      })

    case Repo.insert(changeset) do
      {:ok, _} -> {:ok, :session}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp lock_and_burn_proof(proof, expected_purpose)
       when is_binary(proof) and is_binary(expected_purpose) do
    digest = :crypto.hash(:sha256, proof) |> Base.encode16(case: :lower)
    now = IdentityRecord.utc_now()

    case Repo.one(
           from(p in AuthenticationSetupProof,
             where: p.proof_digest == ^digest,
             lock: "FOR UPDATE"
           )
         ) do
      nil ->
        {:error, :invalid_proof}

      %{used_at: %DateTime{}} ->
        {:error, :invalid_proof}

      %{expires_at: expires_at, purpose: purpose} = row ->
        cond do
          purpose != expected_purpose ->
            {:error, :invalid_proof}

          DateTime.compare(expires_at, now) != :gt ->
            {:error, :expired_proof}

          true ->
            case Repo.update(Ecto.Changeset.change(row, used_at: now)) do
              {:ok, _} -> {:ok, :consumed}
              {:error, _} -> {:error, :unavailable}
            end
        end

      # Rows written before the purpose migration have NULL purpose and fail closed.
      %{expires_at: _} ->
        {:error, :invalid_proof}
    end
  end

  defp lock_and_burn_proof(_, _), do: {:error, :invalid_proof}

  # Test hook: callers may supply :audit_event to force an audit failure and
  # verify atomic rollback. Production callers omit it and get the durable
  # default event inside the same transaction.
  defp append_setup_audit(attrs, installation, user) do
    case Map.get(attrs, :audit_event, Map.get(attrs, "audit_event")) do
      nil ->
        IdentityAuditStore.append(%{
          action: "setup_completed",
          actor_user_public_id: user.public_id,
          target_user_public_id: user.public_id,
          summary: %{mode: installation.bootstrap_mode}
        })

      event when is_map(event) ->
        IdentityRecord.insert_audit(event)
    end
  end

  defp append_recovery_audit(attrs, user) do
    case Map.get(attrs, :audit_event, Map.get(attrs, "audit_event")) do
      nil ->
        IdentityAuditStore.append(%{
          action: "recovery_used",
          actor_user_public_id: user.public_id,
          target_user_public_id: user.public_id,
          summary: %{}
        })

      event when is_map(event) ->
        IdentityRecord.insert_audit(event)
    end
  end

  defp bootstrap_mode("operator_required"), do: :operator_required
  defp bootstrap_mode(_), do: :first_run

  defp initial_superadmin_public_id(%AuthenticationInstallation{initial_superadmin_user_id: nil}),
    do: nil

  defp initial_superadmin_public_id(%AuthenticationInstallation{initial_superadmin_user_id: id}) do
    case Repo.get(IdentityUser, id) do
      nil -> nil
      user -> user.public_id
    end
  end
end
