defmodule Vxpipe.Persistence.Schema.AuthenticationSetupProof do
  use Ecto.Schema
  import Ecto.Changeset

  schema "authentication_setup_proofs" do
    field(:proof_digest, :string, redact: true)
    field(:purpose, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:used_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(proof, attributes) do
    proof
    |> cast(attributes, [:proof_digest, :purpose, :expires_at, :used_at])
    |> validate_required([:proof_digest, :purpose, :expires_at])
    |> validate_inclusion(:purpose, ["setup", "recovery"])
    |> unique_constraint(:proof_digest)
    |> check_constraint(:expires_at, name: :authentication_setup_proofs_expiry)
  end
end
