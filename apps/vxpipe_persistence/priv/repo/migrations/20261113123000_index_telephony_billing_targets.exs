defmodule Vxpipe.Persistence.Repo.Migrations.IndexTelephonyBillingTargets do
  use Ecto.Migration

  def change do
    create(
      index(
        :usage_observations,
        ["(provider->>'name')", "(provider->>'operation_id')", "(provider->>'session_id')"],
        where: "capability = 'telephony'",
        name: :usage_observations_telephony_billing_target_index
      )
    )
  end
end
