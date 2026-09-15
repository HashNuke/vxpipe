defmodule Vxpipe.Persistence.Repo.Migrations.ScopeTelephonyLegIdentity do
  use Ecto.Migration

  def change do
    alter table(:telephony_legs) do
      # Historical rows stay unbound; current aliases cannot supply their original identity.
      add(:service_id, :uuid)
    end

    drop(unique_index(:telephony_legs, [:provider, :service, :provider_event_id]))
    drop(unique_index(:telephony_legs, [:provider, :service, :provider_call_leg_id]))

    create(
      unique_index(:telephony_legs, [:tenant_id, :service_id, :provider, :provider_event_id],
        name: :telephony_legs_tenant_service_event_index
      )
    )

    create(
      unique_index(:telephony_legs, [:tenant_id, :service_id, :provider, :provider_call_leg_id],
        name: :telephony_legs_tenant_service_leg_index
      )
    )
  end
end
