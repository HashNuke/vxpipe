defmodule Vxpipe.Persistence.Schema.Call do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{
    Admission,
    CallArtifact,
    CallDetailsPublication,
    CallSpecRevision,
    JoinToken,
    TelephonyLeg,
    Tenant,
    VariableSnapshot
  }

  @derive {Inspect,
           except: [:initial_variables, :resolved_plan, :idempotency_key, :idempotency_digest]}

  schema "calls" do
    field(:public_id, Ecto.UUID)
    field(:participant_routes, :map)
    field(:entry_caller, :string)
    field(:entry_receiver, :string)
    field(:initial_variables, :map)
    field(:resolved_plan, :binary)
    field(:plan_digest, :binary)

    field(:outgoing_outcome, Ecto.Enum,
      values: [:answered, :no_answer, :busy, :rejected, :failed, :machine, :unknown]
    )

    field(:idempotency_key, :string)
    field(:dial_submitted_at, :utc_datetime_usec)
    field(:answered_at, :utc_datetime_usec)
    field(:dial_ended_at, :utc_datetime_usec)
    field(:idempotency_digest, :binary)

    field(:state, Ecto.Enum, values: [:prepared, :admitting, :running, :ended, :failed])

    field(:room_id, Ecto.UUID)
    field(:created_at, :utc_datetime_usec)
    field(:started_at, :utc_datetime_usec)
    field(:ended_at, :utc_datetime_usec)
    field(:incarnation_id, :string)

    field(:terminal_reason, Ecto.Enum,
      values: [:room_start_failed, :session_start_failed, :startup_unknown]
    )

    belongs_to(:tenant, Tenant)
    belongs_to(:call_spec_revision, CallSpecRevision)
    has_many(:join_tokens, JoinToken)
    has_many(:admissions, Admission)
    has_many(:telephony_legs, TelephonyLeg)
    has_many(:variable_snapshots, VariableSnapshot)
    has_many(:artifacts, CallArtifact)
    has_many(:details_publications, CallDetailsPublication)
    belongs_to(:latest_variables_snapshot, VariableSnapshot)
    belongs_to(:latest_details_publication, CallDetailsPublication)

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
      :outgoing_outcome,
      :dial_submitted_at,
      :answered_at,
      :dial_ended_at,
      :idempotency_key,
      :idempotency_digest,
      :state,
      :room_id,
      :created_at,
      :started_at,
      :ended_at,
      :incarnation_id,
      :terminal_reason,
      :tenant_id,
      :call_spec_revision_id
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
      :call_spec_revision_id
    ])
    |> validate_length(:entry_caller, min: 1, max: 128)
    |> validate_length(:entry_receiver, min: 1, max: 128)
    |> validate_binary_size(:plan_digest, 32)
    |> validate_binary_size(:idempotency_digest, 32)
    |> check_constraint(:outgoing_outcome, name: :calls_outgoing_outcome)
    |> check_constraint(:idempotency_digest, name: :calls_idempotency_digest)
    |> unique_constraint(:idempotency_key, name: :calls_tenant_idempotency_key_index)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:call_spec_revision_id)
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

  def end_changeset(call, ended_at) do
    call
    |> change(state: :ended, terminal_reason: nil, ended_at: ended_at)
    |> check_constraint(:state, name: :calls_state)
  end

  def latest_variables_snapshot_changeset(call, snapshot_id) do
    change(call, latest_variables_snapshot_id: snapshot_id)
  end

  def latest_details_publication_changeset(call, publication_id) do
    change(call, latest_details_publication_id: publication_id)
  end

  defp validate_binary_size(changeset, field, expected_size) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and byte_size(value) == expected_size,
        do: [],
        else: [{field, "must contain exactly #{expected_size} bytes"}]
    end)
  end
end
