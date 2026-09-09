defmodule Vxpipe.Persistence.Repo.Migrations.CreateCallVariableHistory do
  use Ecto.Migration

  def change do
    create table(:call_variable_snapshots) do
      add(:public_id, :string, null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:kind, :string, null: false)
      add(:room_id, :uuid, null: false)
      add(:incarnation_id, :string, null: false)
      add(:global_revision, :bigint, null: false)
      add(:sections, :map, null: false)
      add(:source_policy, :map, null: false)
      add(:command_id, :string)
      add(:participant_id, :string)
      add(:activation_id, :string)
      add(:source_participant_id, :string)
      add(:correlation_id, :string)
      add(:tool_call_id, :string)
      add(:section, :string)
      add(:section_revision, :bigint)
      add(:occurred_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:call_variable_snapshots, [:call_id, :public_id]))

    create(
      unique_index(
        :call_variable_snapshots,
        [:call_id, :incarnation_id, :global_revision],
        name: :call_variable_snapshots_call_incarnation_revision_index
      )
    )

    create(index(:call_variable_snapshots, [:call_id, :occurred_at]))

    create(
      constraint(:call_variable_snapshots, :call_variable_snapshots_kind,
        check: "kind IN ('baseline', 'update')"
      )
    )

    create(
      constraint(:call_variable_snapshots, :call_variable_snapshots_revision,
        check: "global_revision >= 0 AND (section_revision IS NULL OR section_revision > 0)"
      )
    )

    alter table(:calls) do
      add(
        :latest_variables_snapshot_id,
        references(:call_variable_snapshots, on_delete: :nilify_all)
      )
    end

    create(index(:calls, [:latest_variables_snapshot_id]))
  end
end
