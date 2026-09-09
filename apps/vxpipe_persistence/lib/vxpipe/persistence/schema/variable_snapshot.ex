defmodule Vxpipe.Persistence.Schema.VariableSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Call

  @derive {Inspect, except: [:sections]}

  schema "call_variable_snapshots" do
    field :public_id, :string
    field :kind, Ecto.Enum, values: [:baseline, :update]
    field :room_id, Ecto.UUID
    field :incarnation_id, :string
    field :global_revision, :integer
    field :sections, :map
    field :source_policy, :map
    field :command_id, :string
    field :participant_id, :string
    field :activation_id, :string
    field :source_participant_id, :string
    field :correlation_id, :string
    field :tool_call_id, :string
    field :section, :string
    field :section_revision, :integer
    field :occurred_at, :utc_datetime_usec

    belongs_to :call, Call

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(snapshot, attributes) do
    snapshot
    |> cast(attributes, [
      :public_id,
      :call_id,
      :kind,
      :room_id,
      :incarnation_id,
      :global_revision,
      :sections,
      :source_policy,
      :command_id,
      :participant_id,
      :activation_id,
      :source_participant_id,
      :correlation_id,
      :tool_call_id,
      :section,
      :section_revision,
      :occurred_at
    ])
    |> validate_required([
      :public_id,
      :call_id,
      :kind,
      :room_id,
      :incarnation_id,
      :global_revision,
      :sections,
      :source_policy,
      :occurred_at
    ])
    |> validate_number(:global_revision, greater_than_or_equal_to: 0)
    |> validate_length(:public_id, min: 1, max: 256)
    |> validate_length(:incarnation_id, min: 1, max: 256)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint([:call_id, :public_id])
    |> unique_constraint([:call_id, :incarnation_id, :global_revision],
      name: :call_variable_snapshots_call_incarnation_revision_index
    )
    |> check_constraint(:kind, name: :call_variable_snapshots_kind)
    |> check_constraint(:global_revision, name: :call_variable_snapshots_revision)
  end
end
