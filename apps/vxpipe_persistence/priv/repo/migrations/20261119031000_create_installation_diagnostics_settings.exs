defmodule Vxpipe.Persistence.Repo.Migrations.CreateInstallationDiagnosticsSettings do
  use Ecto.Migration

  def change do
    create table(:installation_diagnostics_settings, primary_key: false) do
      add(:key, :text, primary_key: true)
      add(:enabled, :boolean, null: false, default: false)
      add(:revision, :bigint, null: false, default: 0)
      add(:updated_by, :uuid)
      add(:updated_at, :utc_datetime_usec)
    end

    create(
      constraint(:installation_diagnostics_settings, :diagnostics_settings_singleton,
        check: "key = 'default'"
      )
    )

    create(
      constraint(:installation_diagnostics_settings, :diagnostics_settings_revision,
        check: "revision >= 0"
      )
    )

    create(
      constraint(:installation_diagnostics_settings, :diagnostics_settings_attribution,
        check:
          "(revision = 0 AND enabled = false AND updated_by IS NULL AND updated_at IS NULL) OR (revision > 0 AND updated_by IS NOT NULL AND updated_at IS NOT NULL)"
      )
    )

    execute(
      "INSERT INTO installation_diagnostics_settings (key) VALUES ('default')",
      "DELETE FROM installation_diagnostics_settings WHERE key = 'default'"
    )
  end
end
