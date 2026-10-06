defmodule Vxpipe.Calls.PreparedCall do
  @moduledoc "A durable call preparation with its immutable resolved runtime plan."

  alias Vxpipe.CallEngine.ResolvedCallPlan

  @derive {Inspect, except: [:initial_variables, :plan, :idempotency_key, :idempotency_digest]}
  @enforce_keys [
    :id,
    :tenant_key,
    :call_spec_id,
    :call_spec_revision,
    :schema_version,
    :participant_routes,
    :entry_caller,
    :entry_receiver,
    :initial_variables,
    :plan,
    :plan_digest,
    :state,
    :room_id,
    :created_at,
    :started_at,
    :ended_at,
    :incarnation_id,
    :terminal_reason
  ]
  defstruct @enforce_keys ++
              [
                outgoing_outcome: nil,
                dial_submitted_at: nil,
                answered_at: nil,
                dial_ended_at: nil,
                idempotency_key: nil,
                idempotency_digest: nil
              ]

  @type state :: :prepared | :admitting | :running | :ended | :failed
  @type outgoing_outcome ::
          :answered | :no_answer | :busy | :rejected | :failed | :machine | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          call_spec_id: String.t(),
          call_spec_revision: pos_integer(),
          schema_version: String.t(),
          participant_routes: %{String.t() => String.t()},
          entry_caller: String.t(),
          entry_receiver: String.t(),
          initial_variables: map(),
          plan: ResolvedCallPlan.t(),
          plan_digest: binary(),
          outgoing_outcome: nil | outgoing_outcome(),
          dial_submitted_at: nil | DateTime.t(),
          answered_at: nil | DateTime.t(),
          dial_ended_at: nil | DateTime.t(),
          idempotency_key: nil | String.t(),
          idempotency_digest: nil | binary(),
          state: state(),
          room_id: String.t(),
          created_at: DateTime.t(),
          started_at: nil | DateTime.t(),
          ended_at: nil | DateTime.t(),
          incarnation_id: nil | String.t(),
          terminal_reason: nil | :room_start_failed | :session_start_failed | :startup_unknown
        }
end
