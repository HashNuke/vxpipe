defmodule Vxpipe.Persistence.Repo.Migrations.AddRecordingDeduplicationEvidence do
  use Ecto.Migration

  def up do
    alter table(:call_artifacts) do
      add(:duplicate_frames, :integer, null: false, default: 0)
      add(:selected_connection_ids, {:array, :string}, null: false, default: [])
    end
  end

  def down do
    alter table(:call_artifacts) do
      remove(:selected_connection_ids)
      remove(:duplicate_frames)
    end
  end
end
