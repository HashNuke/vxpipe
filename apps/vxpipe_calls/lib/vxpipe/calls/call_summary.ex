defmodule Vxpipe.Calls.CallSummary do
  @moduledoc "A bounded, non-payload-bearing call row for authorized inspection."

  @enforce_keys [
    :id,
    :tenant_key,
    :definition_id,
    :definition_revision,
    :state,
    :created_at,
    :started_at,
    :ended_at,
    :terminal_reason
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_key: String.t(),
          definition_id: String.t(),
          definition_revision: pos_integer(),
          state: :prepared | :admitting | :running | :ended | :failed,
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          terminal_reason: atom() | nil
        }
end
