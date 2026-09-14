defmodule Vxpipe.Persistence.Schema.Admission do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{Call, JoinToken}

  schema "call_admissions" do
    field :participant_key, Ecto.UUID
    field :participant_ref, :string
    field :accepted_at, :utc_datetime_usec
    field :released_at, :utc_datetime_usec

    belongs_to :call, Call
    belongs_to :join_token, JoinToken

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(admission, attributes) do
    admission
    |> cast(attributes, [
      :participant_key,
      :participant_ref,
      :accepted_at,
      :call_id,
      :join_token_id
    ])
    |> validate_required([
      :participant_key,
      :participant_ref,
      :accepted_at,
      :call_id,
      :join_token_id
    ])
    |> validate_length(:participant_ref, min: 1, max: 128)
    |> foreign_key_constraint(:call_id)
    |> foreign_key_constraint(:join_token_id)
    |> unique_constraint(:join_token_id)
    |> unique_constraint(:participant_ref,
      name: :call_admissions_call_id_participant_ref_index
    )
  end
end
