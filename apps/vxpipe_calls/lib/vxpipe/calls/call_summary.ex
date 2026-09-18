defmodule Vxpipe.Calls.CallSummary do
  @moduledoc "A bounded, non-payload-bearing call row for authorized inspection."

  @enforce_keys [
    :id,
    :tenant_key,
    :call_spec_id,
    :call_spec_revision,
    :state,
    :created_at,
    :started_at,
    :ended_at,
    :terminal_reason,
    :latest_variable_revision
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          call_spec_id: String.t(),
          call_spec_revision: pos_integer(),
          state: :prepared | :admitting | :running | :ended | :failed,
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          terminal_reason: atom() | nil,
          latest_variable_revision: non_neg_integer() | nil
        }
end
