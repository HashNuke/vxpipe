defmodule Vxpipe.Persistence.Repo.Migrations.CreateUsageProjections do
  use Ecto.Migration

  def change do
    create table(:usage_observations) do
      add(:public_id, :string, null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:attempt_id, :string, null: false)
      add(:capability, :string, null: false)
      add(:delivery_id, :string)
      add(:source_sequence, :bigint)
      add(:provider, :map, null: false)
      add(:attribution, :map, null: false)
      add(:measurement, :map)
      add(:outcome, :string, null: false)
      add(:observed_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:usage_observations, [:call_id, :public_id]))
    create(index(:usage_observations, [:call_id, :attempt_id]))
    create(index(:usage_observations, [:call_id, :capability]))

    create(
      constraint(:usage_observations, :usage_observations_capability,
        check:
          "capability IN ('model_inference', 'speech_to_text', 'text_to_speech', 'tool', 'telephony')"
      )
    )

    create(
      constraint(:usage_observations, :usage_observations_outcome,
        check: "outcome IN ('in_progress', 'succeeded', 'failed', 'cancelled', 'unknown')"
      )
    )

    create(
      constraint(:usage_observations, :usage_observations_source_sequence,
        check: "source_sequence IS NULL OR source_sequence >= 0"
      )
    )

    create table(:usage_amounts) do
      add(:public_id, :string, null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:attempt_id, :string, null: false)
      add(:capability, :string, null: false)
      add(:provider, :map, null: false)
      add(:attribution, :map, null: false)
      add(:component, :string, null: false)
      add(:unit, :string, null: false)
      add(:currency, :string)
      add(:quantity, :numeric, null: false)
      add(:mode, :string, null: false)
      add(:status, :string, null: false)
      add(:provenance, :string, null: false)
      add(:included_in, :string)
      add(:observation_ids, {:array, :string}, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:usage_amounts, [:call_id, :public_id]))
    create(index(:usage_amounts, [:call_id, :capability]))

    create(
      constraint(:usage_amounts, :usage_amounts_capability,
        check:
          "capability IN ('model_inference', 'speech_to_text', 'text_to_speech', 'tool', 'telephony')"
      )
    )

    create(
      constraint(:usage_amounts, :usage_amounts_unit,
        check: "unit IN ('tokens', 'characters', 'milliseconds', 'requests', 'currency')"
      )
    )

    create(
      constraint(:usage_amounts, :usage_amounts_currency,
        check:
          "(unit = 'currency' AND currency ~ '^[A-Z]{3}$') OR (unit <> 'currency' AND currency IS NULL)"
      )
    )

    create(constraint(:usage_amounts, :usage_amounts_quantity, check: "quantity >= 0"))

    create(
      constraint(:usage_amounts, :usage_amounts_mode,
        check: "mode IN ('delta', 'cumulative')"
      )
    )

    create(
      constraint(:usage_amounts, :usage_amounts_status,
        check: "status IN ('estimate', 'final', 'correction')"
      )
    )

    create(
      constraint(:usage_amounts, :usage_amounts_provenance,
        check:
          "provenance IN ('provider_reported', 'locally_measured', 'library_estimate', 'billing_lookup')"
      )
    )

    create(
      constraint(:usage_amounts, :usage_amounts_observation_ids,
        check: "array_length(observation_ids, 1) >= 1"
      )
    )
  end
end
