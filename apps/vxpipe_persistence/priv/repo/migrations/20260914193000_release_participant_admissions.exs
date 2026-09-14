defmodule Vxpipe.Persistence.Repo.Migrations.ReleaseParticipantAdmissions do
  use Ecto.Migration

  def change do
    alter table(:call_admissions) do
      add(:released_at, :utc_datetime_usec)
    end

    drop(unique_index(:call_admissions, [:call_id, :participant_ref]))

    create(
      unique_index(:call_admissions, [:call_id, :participant_ref], where: "released_at IS NULL")
    )
  end
end
