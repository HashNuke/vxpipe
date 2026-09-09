defmodule Vxpipe.Persistence.Repo.Migrations.CreateCallFactHistory do
  use Ecto.Migration

  def change do
    create table(:call_facts) do
      add(:public_id, :string, null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:kind, :string, null: false)
      add(:sequence, :bigint, null: false)
      add(:room_id, :uuid, null: false)
      add(:incarnation_id, :string, null: false)
      add(:participant_id, :string)
      add(:activation_id, :string)
      add(:source_participant_id, :string)
      add(:connection_id, :string)
      add(:command_id, :string)
      add(:correlation_id, :string)
      add(:tool_call_id, :string)
      add(:public_sequence, :bigint)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:source_policy, :map, null: false)
      add(:payload, :map, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:call_facts, [:call_id, :public_id]))

    create(
      unique_index(:call_facts, [:call_id, :incarnation_id, :sequence],
        name: :call_facts_call_incarnation_sequence_index
      )
    )

    create(index(:call_facts, [:call_id, :occurred_at]))
    create(index(:call_facts, [:call_id, :kind]))

    create(
      constraint(:call_facts, :call_facts_sequence,
        check: "sequence > 0"
      )
    )

    create(
      constraint(:call_facts, :call_facts_public_sequence,
        check: "public_sequence IS NULL OR public_sequence > 0"
      )
    )
  end
end
