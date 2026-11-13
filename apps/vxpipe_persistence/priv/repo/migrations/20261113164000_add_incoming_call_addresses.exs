defmodule Vxpipe.Persistence.Repo.Migrations.AddIncomingCallAddresses do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add(:incoming_from, :string, size: 128)
      add(:incoming_to, :string, size: 128)
    end
  end
end
