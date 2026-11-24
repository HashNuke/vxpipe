defmodule Vxpipe.Persistence.Repo.Migrations.AddTelephonyLegRecovery do
  use Ecto.Migration

  def change do
    alter table(:telephony_legs) do
      add(:recovery, :map, null: false, default: %{})
    end
  end
end
