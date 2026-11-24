defmodule Vxpipe.Persistence.Repo.Migrations.IndexPendingCarrierRecovery do
  use Ecto.Migration

  def change do
    create(
      index(:telephony_legs, [:id],
        name: :telephony_legs_pending_carrier_recovery,
        where:
          "recovery <> '{}'::jsonb AND NOT jsonb_exists(recovery, 'carrier_unknown') AND NOT jsonb_exists(recovery, 'carrier_ended') AND NOT jsonb_exists(recovery, 'transfer_bridged')"
      )
    )
  end
end
