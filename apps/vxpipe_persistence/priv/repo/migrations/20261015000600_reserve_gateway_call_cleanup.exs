defmodule Vxpipe.Persistence.Repo.Migrations.ReserveGatewayCallCleanup do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add(:gateway_cleanup_required, :boolean, null: false, default: false)
      add(:gateway_cleanup_completed_at, :utc_datetime_usec)
    end

    create(
      constraint(:calls, :calls_gateway_cleanup_binding,
        check:
          "NOT gateway_cleanup_required OR (incarnation_id IS NOT NULL AND incarnation_binding_verified)"
      )
    )

    create(
      constraint(:calls, :calls_gateway_cleanup_completion,
        check:
          "gateway_cleanup_completed_at IS NULL OR (gateway_cleanup_required AND " <>
            "gateway_cleanup_completed_at >= created_at AND " <>
            "(started_at IS NULL OR gateway_cleanup_completed_at >= started_at))"
      )
    )
  end
end
