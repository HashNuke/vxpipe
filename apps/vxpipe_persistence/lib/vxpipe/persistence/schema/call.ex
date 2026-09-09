defmodule Vxpipe.Persistence.Schema.Call do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{
    Admission,
    DefinitionRevision,
    JoinToken,
    Tenant,
    VariableSnapshot
  }

  @derive {Inspect, except: [:initial_variables, :resolved_plan]}

  schema "calls" do
    field :public_id, Ecto.UUID
    field :participant_routes, :map
    field :entry_caller, :string
    field :entry_receiver, :string
    field :initial_variables, :map
    field :resolved_plan, :binary
    field :plan_digest, :binary

    field :state, Ecto.Enum,
      values: [:prepared, :admitting, :running, :ended, :failed]

    field :room_id, Ecto.UUID
    field :created_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :incarnation_id, :string

    field :terminal_reason, Ecto.Enum,
      values: [:room_start_failed, :session_start_failed, :startup_unknown]

    belongs_to :tenant, Tenant
    belongs_to :definition_revision, DefinitionRevision
    has_many :join_tokens, JoinToken
    has_many :admissions, Admission
    has_many :variable_snapshots, VariableSnapshot
    belongs_to :latest_variables_snapshot, VariableSnapshot

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(call, attributes) do
    call
    |> cast(attributes, [
      :public_id,
      :participant_routes,
      :entry_caller,
      :entry_receiver,
      :initial_variables,
      :resolved_plan,
      :plan_digest,
      :state,
      :room_id,
      :created_at,
      :started_at,
      :ended_at,
      :incarnation_id,
      :terminal_reason,
      :tenant_id,
      :definition_revision_id
    ])
    |> validate_required([
      :public_id,
      :participant_routes,
      :entry_caller,
      :entry_receiver,
      :initial_variables,
      :resolved_plan,
      :plan_digest,
      :state,
      :room_id,
      :created_at,
      :tenant_id,
      :definition_revision_id
    ])
    |> validate_length(:entry_caller, min: 1, max: 128)
    |> validate_length(:entry_receiver, min: 1, max: 128)
    |> validate_binary_size(:plan_digest, 32)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:definition_revision_id)
    |> unique_constraint(:public_id)
  end

  def state_changeset(call, state) do
    call
    |> change(state: state)
    |> check_constraint(:state, name: :calls_state)
  end

  def start_changeset(call, incarnation_id, started_at) do
    call
    |> change(
      state: :running,
      incarnation_id: incarnation_id,
      started_at: started_at,
      terminal_reason: nil
    )
    |> check_constraint(:state, name: :calls_state)
  end

  def failure_changeset(call, reason, failed_at) do
    call
    |> change(state: :failed, terminal_reason: reason, ended_at: failed_at)
    |> check_constraint(:state, name: :calls_state)
    |> check_constraint(:terminal_reason, name: :calls_terminal_reason)
  end

  def latest_variables_snapshot_changeset(call, snapshot_id) do
    change(call, latest_variables_snapshot_id: snapshot_id)
  end

  defp validate_binary_size(changeset, field, expected_size) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and byte_size(value) == expected_size,
        do: [],
        else: [{field, "must contain exactly #{expected_size} bytes"}]
    end)
  end
end
