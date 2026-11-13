defmodule Vxpipe.Persistence.Repo.Migrations.AddCallerIdentity do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add(:caller_id_number, :string, size: 16)
      add(:caller_id_name, :string, size: 128)
      add(:caller_sip_uri, :string, size: 512)
    end
  end
end
