defmodule Vxpipe.Persistence.Repo.Migrations.AddCallAdmissionLifecycle do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add :incarnation_id, :string
      add :terminal_reason, :string
    end

    create constraint(:calls, :calls_terminal_reason,
             check:
               "terminal_reason IS NULL OR terminal_reason IN ('room_start_failed', 'session_start_failed', 'startup_unknown')"
           )
  end
end
