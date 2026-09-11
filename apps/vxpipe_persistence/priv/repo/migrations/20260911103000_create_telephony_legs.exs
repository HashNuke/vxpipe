defmodule Vxpipe.Persistence.Repo.Migrations.CreateTelephonyLegs do
  use Ecto.Migration

  def change do
    create table(:telephony_legs) do
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:provider, :string, null: false)
      add(:service, :string, null: false)
      add(:provider_event_id, :string, null: false)
      add(:provider_connection_id, :string, null: false)
      add(:provider_call_control_id, :string, null: false)
      add(:provider_call_leg_id, :string, null: false)
      add(:provider_call_session_id, :string, null: false)
      add(:participant_ref, :string, null: false)
      add(:participant_id, :string, null: false)
      add(:state, :string, null: false)
      add(:accepted_at, :utc_datetime_usec, null: false)
      add(:incarnation_id, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:telephony_legs, [:provider, :service, :provider_event_id]))
    create(unique_index(:telephony_legs, [:provider, :service, :provider_call_leg_id]))
    create(index(:telephony_legs, [:tenant_id, :call_id, :participant_ref]))
  end
end
