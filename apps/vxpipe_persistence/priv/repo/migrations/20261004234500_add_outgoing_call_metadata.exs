defmodule Vxpipe.Persistence.Repo.Migrations.AddOutgoingCallMetadata do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add(:outgoing_outcome, :string)
      add(:idempotency_key, :text)
      add(:idempotency_digest, :binary)
    end

    create(
      unique_index(:calls, [:tenant_id, :idempotency_key],
        where: "idempotency_key IS NOT NULL",
        name: :calls_tenant_idempotency_key_index
      )
    )

    create(
      constraint(:calls, :calls_outgoing_outcome,
        check:
          "outgoing_outcome IS NULL OR outgoing_outcome IN ('answered', 'no_answer', 'busy', 'rejected', 'failed', 'machine', 'unknown')"
      )
    )

    create(
      constraint(:calls, :calls_idempotency_digest,
        check:
          "(idempotency_key IS NULL AND idempotency_digest IS NULL) OR " <>
            "(idempotency_key IS NOT NULL AND idempotency_digest IS NOT NULL AND octet_length(idempotency_digest) = 32)"
      )
    )
  end
end
