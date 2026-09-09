defmodule Vxpipe.Persistence.Schema.JoinToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{Admission, Call, Tenant}

  @derive {Inspect, except: [:digest]}

  schema "join_tokens" do
    field :public_id, Ecto.UUID
    field :participant_key, Ecto.UUID
    field :participant_ref, :string
    field :digest, :binary
    field :issued_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    belongs_to :tenant, Tenant
    belongs_to :call, Call
    has_one :admission, Admission

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(token, attributes) do
    token
    |> cast(attributes, [
      :public_id,
      :participant_key,
      :participant_ref,
      :digest,
      :issued_at,
      :expires_at,
      :consumed_at,
      :tenant_id,
      :call_id
    ])
    |> validate_required([
      :public_id,
      :participant_key,
      :participant_ref,
      :digest,
      :issued_at,
      :expires_at,
      :tenant_id,
      :call_id
    ])
    |> validate_length(:participant_ref, min: 1, max: 128)
    |> validate_binary_size(:digest, 32)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint(:public_id)
    |> unique_constraint(:digest)
    |> check_constraint(:expires_at, name: :join_tokens_expiry_order)
  end

  def consume_changeset(token, consumed_at) do
    change(token, consumed_at: consumed_at)
  end

  defp validate_binary_size(changeset, field, expected_size) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and byte_size(value) == expected_size,
        do: [],
        else: [{field, "must contain exactly #{expected_size} bytes"}]
    end)
  end
end
