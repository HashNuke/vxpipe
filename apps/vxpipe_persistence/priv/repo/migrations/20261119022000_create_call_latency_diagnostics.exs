defmodule Vxpipe.Persistence.Repo.Migrations.CreateCallLatencyDiagnostics do
  use Ecto.Migration

  def change do
    create table(:call_latency_runs) do
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:public_id, :text, null: false)
      add(:revision, :bigint, null: false)
      add(:record, :map, null: false)
      add(:profile, :map, null: false)
      add(:state, :string, null: false)
      add(:heartbeat_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:call_latency_runs, [:call_id, :public_id]))

    create(
      constraint(:call_latency_runs, :latency_run_id_size,
        check: "octet_length(public_id) BETWEEN 1 AND 256"
      )
    )

    create(constraint(:call_latency_runs, :latency_run_positive_revision, check: "revision > 0"))

    create(
      constraint(:call_latency_runs, :latency_run_state,
        check: "state IN ('running', 'closed', 'incomplete')"
      )
    )

    create table(:call_turn_diagnostics) do
      add(:run_id, references(:call_latency_runs, on_delete: :delete_all), null: false)
      add(:turn_id, :text, null: false)
      add(:revision, :bigint, null: false)
      add(:record, :map, null: false)
      add(:durations_us, :map, null: false)
      add(:quality, :string, null: false)
    end

    create(unique_index(:call_turn_diagnostics, [:run_id, :turn_id]))

    create(
      constraint(:call_turn_diagnostics, :turn_diagnostic_id_size,
        check: "octet_length(turn_id) BETWEEN 1 AND 256"
      )
    )

    create(
      constraint(:call_turn_diagnostics, :turn_diagnostic_positive_revision,
        check: "revision > 0"
      )
    )

    create(
      constraint(:call_turn_diagnostics, :turn_diagnostic_quality,
        check: "quality IN ('available', 'incomplete', 'unavailable')"
      )
    )
  end
end
