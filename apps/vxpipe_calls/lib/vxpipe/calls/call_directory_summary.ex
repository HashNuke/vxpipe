defmodule Vxpipe.Calls.CallDirectorySummary do
  @moduledoc "One payload-free call row for the installation-operator directory."

  @enforce_keys [
    :id,
    :call_spec_id,
    :call_spec_name,
    :call_spec_revision,
    :state,
    :created_at,
    :started_at,
    :ended_at,
    :terminal_reason,
    :archive_state
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          call_spec_id: String.t(),
          call_spec_name: String.t() | nil,
          call_spec_revision: pos_integer(),
          state: :prepared | :admitting | :running | :ended | :failed,
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          ended_at: DateTime.t() | nil,
          terminal_reason: atom() | nil,
          archive_state: :complete | :incomplete | :unconfirmed
        }
end
