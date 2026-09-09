defmodule Vxpipe.Calls.CallListPage do
  @moduledoc "One bounded page of tenant-scoped calls available for inspection."

  alias Vxpipe.Calls.CallSummary

  @enforce_keys [:calls, :next_cursor]
  defstruct @enforce_keys

  @type t :: %__MODULE__{calls: [CallSummary.t()], next_cursor: String.t() | nil}
end
