defmodule Vxpipe.Persistence.Repo.Migrations.AllowOptionalTelephonySessionId do
  use Ecto.Migration

  def change do
    alter table(:telephony_legs) do
      modify(:provider_call_session_id, :string, null: true, from: {:string, null: false})
    end
  end
end
