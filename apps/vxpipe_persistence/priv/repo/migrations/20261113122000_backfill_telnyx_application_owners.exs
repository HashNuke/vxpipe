defmodule Vxpipe.Persistence.Repo.Migrations.BackfillTelnyxApplicationOwners do
  use Ecto.Migration

  def up, do: backfill(repo())
  def down, do: :ok

  # Existing scoped Telnyx bindings always had an explicit tenant application.
  # Preserve existing ownership if this runs against newer data too.
  def backfill(repo) do
    Vxpipe.CallEngine.ResolvedCallPlan.ensure_data_loaded!()

    for [id, encoded] <- repo.query!("SELECT id, resolved_plan FROM calls").rows do
      original = :erlang.binary_to_term(encoded, [:safe])
      migrated = migrate(original)

      if migrated != original do
        updated = :erlang.term_to_binary(migrated, [:deterministic])

        repo.query!(
          "UPDATE calls SET resolved_plan = $1, plan_digest = $2 WHERE id = $3",
          [updated, :crypto.hash(:sha256, updated), id], log: false)
      end
    end

    :ok
  end

  defp migrate(%{__struct__: Vxpipe.CallEngine.Telephony.ServiceReference} = reference) do
    owner =
      case reference do
        %{provider: "telnyx", credential_name: "telnyx", tenant_id: tenant} -> {:tenant, tenant}
        _other -> nil
      end

    Map.put_new(reference, :application_owner, owner)
  end

  defp migrate(value) when is_map(value),
    do: Map.new(Map.to_list(value), fn {key, nested} -> {key, migrate(nested)} end)

  defp migrate(value) when is_list(value), do: Enum.map(value, &migrate/1)

  defp migrate(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&migrate/1) |> List.to_tuple()

  defp migrate(value), do: value
end
