defmodule Vxpipe.Persistence.IdentitySessionStore do
  @moduledoc "Ecto adapter for the `Vxpipe.Identity.Ports.Sessions` boundary. Only digests are stored."

  @behaviour Vxpipe.Identity.Ports.Sessions

  import Ecto.Query

  alias Vxpipe.Persistence.IdentityRecord
  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.Schema.{AuthenticationInstallation, IdentitySession, IdentityUser}

  @impl true
  def create(attrs) do
    with :ok <- require_completed_installation() do
      now = IdentityRecord.utc_now()

      changeset =
        IdentitySession.changeset(%IdentitySession{}, %{
          public_id: attrs.public_id,
          user_id: fetch_user_id!(attrs.user_public_id),
          token_digest: attrs.digest,
          issued_at: now,
          expires_at: attrs.expires_at
        })

      case Repo.insert(changeset) do
        {:ok, session} ->
          {:ok,
           %{
             public_id: session.public_id,
             user_public_id: attrs.user_public_id,
             expires_at: session.expires_at
           }}

        {:error, _} ->
          {:error, :unavailable}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def fetch_valid(digest, now) do
    with :ok <- require_completed_installation() do
      query =
        from(s in IdentitySession,
          join: u in assoc(s, :user),
          where: s.token_digest == ^digest,
          preload: [user: u]
        )

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        session ->
          cond do
            not is_nil(session.revoked_at) -> {:error, :revoked}
            DateTime.compare(session.expires_at, now) != :gt -> {:error, :expired}
            not is_nil(session.user.disabled_at) -> {:error, :disabled}
            true -> {:ok, %{public_id: session.public_id, user_public_id: session.user.public_id}}
          end
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def revoke_one(digest, now) do
    _ =
      Repo.update_all(
        from(s in IdentitySession, where: s.token_digest == ^digest and is_nil(s.revoked_at)),
        set: [revoked_at: now]
      )

    :ok
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def revoke_for_user(user_public_id, now) do
    {count, _} =
      Repo.update_all(
        from(s in IdentitySession,
          join: u in assoc(s, :user),
          where: u.public_id == ^user_public_id and is_nil(s.revoked_at)
        ),
        set: [revoked_at: now]
      )

    {:ok, count}
  rescue
    _ -> {:error, :unavailable}
  end

  @impl true
  def revoke_for_role(role_public_id, now) do
    {count, _} =
      Repo.update_all(
        from(s in IdentitySession,
          join: u in assoc(s, :user),
          join: r in assoc(u, :role),
          where: r.public_id == ^role_public_id and is_nil(s.revoked_at)
        ),
        set: [revoked_at: now]
      )

    {:ok, count}
  rescue
    _ -> {:error, :unavailable}
  end

  defp fetch_user_id!(user_public_id) do
    Repo.one!(from(u in IdentityUser, where: u.public_id == ^user_public_id, select: u.id))
  end

  defp require_completed_installation do
    case Repo.get(AuthenticationInstallation, "default") do
      nil -> {:error, :missing}
      %{setup_completed_at: nil} -> {:error, :not_complete}
      %{initial_superadmin_user_id: nil} -> {:error, :corrupt}
      %AuthenticationInstallation{} -> :ok
    end
  end
end
