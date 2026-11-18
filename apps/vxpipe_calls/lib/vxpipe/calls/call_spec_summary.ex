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
  defstruct @enforce_keys ++ [published_version: nil, unpublished_changes: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          latest_revision: pos_integer(),
          published_revision: pos_integer() | nil,
          published_version: pos_integer() | nil,
          unpublished_changes: boolean() | nil,
          call_count: non_neg_integer(),
          updated_at: DateTime.t()
        }
end
