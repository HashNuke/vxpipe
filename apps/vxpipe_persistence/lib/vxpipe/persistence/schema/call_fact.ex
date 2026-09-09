defmodule Vxpipe.Persistence.Schema.CallFact do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Call

  @derive {Inspect, except: [:source_policy, :payload]}

  schema "call_facts" do
    field :public_id, :string
    field :kind, :string
    field :sequence, :integer
    field :room_id, Ecto.UUID
    field :incarnation_id, :string
    field :participant_id, :string
    field :activation_id, :string
    field :source_participant_id, :string
    field :connection_id, :string
    field :command_id, :string
    field :correlation_id, :string
    field :tool_call_id, :string
    field :public_sequence, :integer
    field :occurred_at, :utc_datetime_usec
    field :source_policy, :map
    field :payload, :map

    belongs_to :call, Call

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(fact, attributes) do
    fact
    |> cast(attributes, [
      :public_id,
      :call_id,
      :kind,
      :sequence,
      :room_id,
      :incarnation_id,
      :participant_id,
      :activation_id,
      :source_participant_id,
      :connection_id,
      :command_id,
      :correlation_id,
      :tool_call_id,
      :public_sequence,
      :occurred_at,
      :source_policy,
      :payload
    ])
    |> validate_required([
      :public_id,
      :call_id,
      :kind,
      :sequence,
      :room_id,
      :incarnation_id,
      :occurred_at,
      :source_policy,
      :payload
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> validate_number(:public_sequence, greater_than: 0)
    |> validate_length(:public_id, min: 1, max: 256)
    |> validate_length(:incarnation_id, min: 1, max: 256)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint([:call_id, :public_id])
    |> unique_constraint([:call_id, :incarnation_id, :sequence],
      name: :call_facts_call_incarnation_sequence_index
    )
    |> check_constraint(:sequence, name: :call_facts_sequence)
    |> check_constraint(:public_sequence, name: :call_facts_public_sequence)
  end
end
