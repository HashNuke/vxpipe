defmodule Vxpipe.Persistence.Repo.Migrations.IndexPendingCallCleanup do
  use Ecto.Migration

  def change do
    create(
      index(:calls, [:id],
        name: :calls_pending_cleanup_index,
        where:
          "state <> 'ended' AND (hangup_requested_at IS NOT NULL OR " <>
            "(gateway_cleanup_required AND gateway_cleanup_completed_at IS NULL))"
      )
    )
  end
end
