defmodule Vxpipe.Persistence.Repo.Migrations.CreateOperatorLoginChallenges do
  use Ecto.Migration

  def change do
    create table(:operator_login_challenges) do
      add(:token_digest, :binary, null: false)
      add(:code_verifier, :binary, null: false)
      add(:failed_attempts, :integer, null: false, default: 0)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:consumed_at, :utc_datetime_usec)
    end

    create(unique_index(:operator_login_challenges, [:token_digest]))
    create(index(:operator_login_challenges, [:expires_at]))

    create(
      constraint(:operator_login_challenges, :operator_login_challenges_token_digest_size,
        check: "octet_length(token_digest) = 32"
      )
    )

    create(
      constraint(:operator_login_challenges, :operator_login_challenges_code_verifier_size,
        check: "octet_length(code_verifier) = 32"
      )
    )

    create(
      constraint(:operator_login_challenges, :operator_login_challenges_failed_attempts,
        check: "failed_attempts >= 0 AND failed_attempts <= 5"
      )
    )

    create(
      constraint(:operator_login_challenges, :operator_login_challenges_expiry,
        check: "expires_at > issued_at"
      )
    )
  end
end
