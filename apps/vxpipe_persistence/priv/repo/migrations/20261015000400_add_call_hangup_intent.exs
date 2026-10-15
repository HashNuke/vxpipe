defmodule Vxpipe.Persistence.Repo.Migrations.AddCallHangupIntent do
  use Ecto.Migration

  def up do
    alter table(:calls) do
      add(:hangup_requested_at, :utc_datetime_usec)
    end

    drop(constraint(:calls, :calls_terminal_reason))

    create(
      constraint(:calls, :calls_terminal_reason,
        check:
          "terminal_reason IS NULL OR terminal_reason IN ('room_start_failed', 'session_start_failed', 'startup_unknown', 'api_hangup')"
      )
    )
  end

  def down do
    # Older application versions cannot decode the new reason; retain terminal
    # state and end time when explicitly rolling back this migration.
    execute("UPDATE calls SET terminal_reason = NULL WHERE terminal_reason = 'api_hangup'")
    drop(constraint(:calls, :calls_terminal_reason))

    create(
      constraint(:calls, :calls_terminal_reason,
        check:
          "terminal_reason IS NULL OR terminal_reason IN ('room_start_failed', 'session_start_failed', 'startup_unknown')"
      )
    )

    alter table(:calls) do
      remove(:hangup_requested_at)
    end
  end
end
