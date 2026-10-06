defmodule Vxpipe.Persistence.Repo.Migrations.AddOutgoingDialTimestamps do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add(:dial_submitted_at, :utc_datetime_usec)
      add(:answered_at, :utc_datetime_usec)
      add(:dial_ended_at, :utc_datetime_usec)
    end

    create(
      constraint(:calls, :calls_outgoing_times,
        check:
          "(dial_submitted_at IS NULL OR (started_at IS NOT NULL AND dial_submitted_at >= started_at)) AND " <>
            "(answered_at IS NULL OR (outgoing_outcome IS NOT NULL AND outgoing_outcome = 'answered' AND dial_submitted_at IS NOT NULL AND answered_at >= dial_submitted_at)) AND " <>
            "(dial_ended_at IS NULL OR (dial_submitted_at IS NOT NULL AND outgoing_outcome IS NOT NULL AND dial_ended_at >= dial_submitted_at AND (answered_at IS NULL OR dial_ended_at >= answered_at)))"
      )
    )
  end
end
