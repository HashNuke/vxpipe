defmodule Vxpipe.Persistence.Repo.Migrations.AddOutgoingCallNumbers do
  use Ecto.Migration

  # The E.164 number an outgoing call dialed and the service caller ID it was admitted
  # with. Both stay null for incoming and web calls.
  def change do
    alter table(:calls) do
      add(:to_number, :string)
      add(:from_number, :string)
    end

    create(
      constraint(:calls, :calls_outgoing_numbers,
        check:
          "(to_number IS NULL OR to_number ~ '^\\+[1-9][0-9]{1,14}$') AND " <>
            "(from_number IS NULL OR from_number ~ '^\\+[1-9][0-9]{1,14}$')"
      )
    )
  end
end
