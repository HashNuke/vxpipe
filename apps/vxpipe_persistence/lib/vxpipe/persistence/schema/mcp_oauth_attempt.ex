defmodule Vxpipe.Persistence.Schema.MCPOAuthAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenant_mcp_oauth_attempts" do
    field(:public_id, Ecto.UUID)
    belongs_to(:tenant, Vxpipe.Persistence.Schema.Tenant)
    field(:state_digest, :binary, redact: true)
    field(:binding, :map, redact: true)
    field(:expires_at, :utc_datetime_usec)
    field(:claimed_at, :utc_datetime_usec)
    field(:encrypted_payload, :binary, redact: true)
    field(:encryption_key_id, :string)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attributes) do
    record
    |> cast(attributes, [
      :public_id,
      :tenant_id,
      :state_digest,
      :binding,
      :expires_at,
      :claimed_at,
      :encrypted_payload,
      :encryption_key_id
    ])
    |> validate_required([:public_id, :tenant_id, :state_digest, :binding, :expires_at])
    |> unique_constraint(:state_digest)
    |> unique_constraint(:public_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
