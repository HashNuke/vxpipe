defmodule Vxpipe.Persistence.Schema.OperatorLoginChallenge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "operator_login_challenges" do
    field(:token_digest, :binary, redact: true)
    field(:code_verifier, :binary, redact: true)
    field(:failed_attempts, :integer, default: 0)
    field(:issued_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:consumed_at, :utc_datetime_usec)
  end

  def changeset(challenge, attributes) do
    challenge
    |> cast(attributes, [
      :token_digest,
      :code_verifier,
      :failed_attempts,
      :issued_at,
      :expires_at,
      :consumed_at
    ])
    |> validate_required([
      :token_digest,
      :code_verifier,
      :failed_attempts,
      :issued_at,
      :expires_at
    ])
    |> validate_number(:failed_attempts, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> validate_binary_size(:token_digest, 32)
    |> validate_binary_size(:code_verifier, 32)
    |> unique_constraint(:token_digest)
    |> check_constraint(:failed_attempts, name: :operator_login_challenges_failed_attempts)
    |> check_constraint(:expires_at, name: :operator_login_challenges_expiry)
  end

  def consume_changeset(challenge, consumed_at) do
    change(challenge, consumed_at: consumed_at)
  end

  def fail_changeset(challenge) do
    change(challenge, failed_attempts: challenge.failed_attempts + 1)
  end

  defp validate_binary_size(changeset, field, expected_size) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and byte_size(value) == expected_size,
        do: [],
        else: [{field, "must contain exactly #{expected_size} bytes"}]
    end)
  end
end
