defmodule Vxpipe.Calls.CallDetailsRevisionPage do
  @moduledoc "One bounded page of tenant-scoped call-details revisions."

  alias Vxpipe.Calls.CallDetailsRevision

  @enforce_keys [:revisions, :next_cursor]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          revisions: [CallDetailsRevision.t()],
          next_cursor: String.t() | nil
        }
end
