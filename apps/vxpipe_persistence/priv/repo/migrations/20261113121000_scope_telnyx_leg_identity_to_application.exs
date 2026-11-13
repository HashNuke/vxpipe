defmodule Vxpipe.Persistence.Repo.Migrations.ScopeTelnyxLegIdentityToApplication do
  use Ecto.Migration

  def change do
    create(
      unique_index(:telephony_legs, [:provider_connection_id, :provider_event_id],
        where: "provider = 'telnyx'",
        name: :telephony_legs_telnyx_application_event_index
      )
    )

    create(
      unique_index(:telephony_legs, [:provider_connection_id, :provider_call_leg_id],
        where: "provider = 'telnyx'",
        name: :telephony_legs_telnyx_application_leg_index
      )
    )
  end
end
