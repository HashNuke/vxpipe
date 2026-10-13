defmodule Vxpipe.Persistence.Repo.Migrations.AddProofPurpose do
  use Ecto.Migration

  def up do
    alter table(:authentication_setup_proofs) do
      add(:purpose, :string, default: "setup")
    end

    flush()

    # Pre-purpose recovery proofs become setup-purpose and fail closed on
    # recovery use; operators re-issue recovery proofs after deploy.
    execute("UPDATE authentication_setup_proofs SET purpose = 'setup' WHERE purpose IS NULL", "")

    alter table(:authentication_setup_proofs) do
      modify(:purpose, :string, null: false, from: {:string, null: true})
    end

    create(
      constraint(:authentication_setup_proofs, :authentication_setup_proofs_purpose,
        check: "purpose IN ('setup', 'recovery')"
      )
    )
  end

  def down do
    drop(constraint(:authentication_setup_proofs, :authentication_setup_proofs_purpose))

    alter table(:authentication_setup_proofs) do
      remove(:purpose)
    end
  end
end
