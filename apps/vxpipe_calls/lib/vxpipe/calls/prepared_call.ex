defmodule Vxpipe.Calls.PreparedCall do
  @moduledoc "A durable call preparation with its immutable resolved runtime plan."

  alias Vxpipe.CallEngine.ResolvedCallPlan

  @derive {Inspect, except: [:initial_variables, :plan]}
  @enforce_keys [
    :id,
    :tenant_key,
    :definition_id,
    :definition_revision,
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
  defstruct @enforce_keys

  @type state :: :prepared | :admitting | :running | :ended | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          definition_id: String.t(),
          definition_revision: pos_integer(),
          schema_version: String.t(),
          participant_routes: %{String.t() => String.t()},
          entry_caller: String.t(),
          entry_receiver: String.t(),
          initial_variables: map(),
          plan: ResolvedCallPlan.t(),
          plan_digest: binary(),
          state: state(),
          room_id: String.t(),
          created_at: DateTime.t(),
          started_at: nil | DateTime.t(),
          ended_at: nil | DateTime.t(),
          incarnation_id: nil | String.t(),
          terminal_reason: nil | :room_start_failed | :session_start_failed | :startup_unknown
        }
end
