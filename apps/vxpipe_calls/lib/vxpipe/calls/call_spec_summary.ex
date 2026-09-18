defmodule Vxpipe.Calls.CallSpecSummary do
  @moduledoc "Installation-operator summary of one call spec."

  @enforce_keys [
    :id,
    :name,
    :latest_revision,
    :published_revision,
    :call_count,
    :updated_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          latest_revision: pos_integer(),
          published_revision: pos_integer() | nil,
          call_count: non_neg_integer(),
          updated_at: DateTime.t()
        }
end
