defmodule Vxpipe.Persistence.IdentityAuditStore do
  @moduledoc "Append-only safe access-event sink. Summaries are redacted before insert."

  @behaviour Vxpipe.Identity.Ports.Audit

  import Ecto.Query

  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.Schema.{IdentityRole, IdentityUser, UserAccessEvent}

  @impl true
  def append(event) do
    summary = event |> Map.get(:summary, %{}) |> Vxpipe.Identity.Audit.sanitize_summary()

    changeset =
      UserAccessEvent.changeset(%UserAccessEvent{}, %{
        actor_user_id: internal_user_id(Map.get(event, :actor_user_public_id)),
        target_user_id: internal_user_id(Map.get(event, :target_user_public_id)),
        target_role_id: internal_role_id(Map.get(event, :target_role_public_id)),
        action: to_string(Map.get(event, :action, "unknown")),
        summary: summary
      })

    case Repo.insert(changeset) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def recent_events(limit) do
    Repo.all(from(e in UserAccessEvent, order_by: [desc: e.id], limit: ^limit))
  end

  defp internal_user_id(nil), do: nil

  defp internal_user_id(public_id) when is_binary(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} ->
        try do
          Repo.one(from(u in IdentityUser, where: u.public_id == ^public_id, select: u.id))
        rescue
          _ -> nil
        end

      :error ->
        nil
    end
  end

  defp internal_user_id(_), do: nil

  defp internal_role_id(nil), do: nil

  defp internal_role_id(public_id) when is_binary(public_id) do
    case Ecto.UUID.cast(public_id) do
      {:ok, _} ->
        try do
          Repo.one(from(r in IdentityRole, where: r.public_id == ^public_id, select: r.id))
        rescue
          _ -> nil
        end

      :error ->
        nil
    end
  end

  defp internal_role_id(_), do: nil
end
