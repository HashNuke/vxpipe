defmodule Vxpipe.Persistence.DiagnosticsSettingsStore do
  @moduledoc "Atomic installation diagnostics settings with current browser-session authority."
  @behaviour Vxpipe.Identity.Ports.DiagnosticsSettings
  import Ecto.Query
  alias Vxpipe.Identity.DiagnosticsSettings
  alias Vxpipe.Persistence.{IdentityAuditStore, Repo}
  alias Vxpipe.Persistence.Schema.DiagnosticsSettings, as: Settings
  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentitySession, IdentityUser}

  @impl true
  def fetch(actor) do
    transact(fn ->
      with {:ok, expires_at} <- authorize(actor),
           {:ok, row} <- current(false),
           :ok <- unexpired(expires_at),
           do: public(row)
    end)
  end

  @impl true
  def update(actor, enabled, revision) do
    transact(fn ->
      with {:ok, expires_at} <- authorize(actor),
           :ok <- DiagnosticsSettings.validate_change(enabled, revision),
           {:ok, row} <- current(true),
           :ok <- unexpired(expires_at),
           true <- row.revision == revision,
           {:ok, row} <- change(row, actor, enabled) do
        public(row)
      else
        false -> {:error, :conflict}
        error -> error
      end
    end)
  end

  @doc "Internal projection read; never exposed as an unauthenticated browser operation."
  def snapshot do
    with {:ok, row} <- current(false), do: {:ok, %{enabled: row.enabled, revision: row.revision}}
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp transact(operation) do
    Repo.transaction(fn ->
      case operation.() do
        {:error, reason} -> Repo.rollback(reason)
        result -> result
      end
    end)
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp authorize(actor) do
    with :ok <- DiagnosticsSettings.authorize(actor),
         {:ok, user_id} <- Ecto.UUID.cast(actor.user_public_id),
         {:ok, session_id} <- Ecto.UUID.cast(actor.session_public_id) do
      now = DateTime.utc_now()

      query =
        from(u in IdentityUser,
          join: s in IdentitySession,
          on: s.user_id == u.id,
          join: r in IdentityRole,
          on: r.id == u.role_id,
          where:
            u.public_id == ^user_id and s.public_id == ^session_id and
              is_nil(u.disabled_at) and is_nil(s.revoked_at) and s.expires_at > ^now and
              r.kind in ["admin", "superadmin"],
          lock: "FOR UPDATE",
          select: s.expires_at
        )

      case Repo.one(query) do
        nil -> {:error, :forbidden}
        expires_at -> {:ok, expires_at}
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  # Both the authority query and the settings lock can wait. Validate against a
  # fresh time after all locks, while revocation/role changes remain serialized.
  defp unexpired(expires_at) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :forbidden}
  end

  defp current(lock?) do
    query = from(s in Settings, where: s.key == "default")
    query = if lock?, do: from(s in query, lock: "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :unavailable}
      row -> {:ok, row}
    end
  end

  defp change(%{enabled: enabled} = row, _actor, enabled), do: {:ok, row}

  defp change(row, actor, enabled) do
    with {:ok, updated} <-
           row
           |> Settings.changeset(%{
             enabled: enabled,
             revision: row.revision + 1,
             updated_by: actor.user_public_id,
             updated_at: DateTime.utc_now()
           })
           |> Repo.update(),
         :ok <-
           IdentityAuditStore.append(%{
             action: "diagnostics_settings_updated",
             actor_user_public_id: actor.user_public_id,
             summary: %{enabled: enabled, revision: updated.revision}
           }) do
      {:ok, updated}
    end
  end

  defp public(row), do: Map.take(row, [:enabled, :revision, :updated_by, :updated_at])
end
