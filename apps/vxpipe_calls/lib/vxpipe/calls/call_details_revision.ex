defmodule Vxpipe.Calls.CallDetailsRevision do
  @moduledoc "Safe operator metadata for one immutable call-details revision."

  @fields [
    :id,
    :recorded_at,
    :filename,
    :completeness,
    :status,
    :checksum,
    :size_bytes,
    :published_at,
    :latest?
  ]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: String.t(),
          recorded_at: DateTime.t(),
          filename: String.t(),
          completeness: :complete | :incomplete,
          status: :pending | :published,
          checksum: String.t(),
          size_bytes: non_neg_integer(),
          published_at: DateTime.t() | nil,
          latest?: boolean()
        }
end
