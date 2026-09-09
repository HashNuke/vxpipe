defmodule Vxpipe.Calls.CallDetailPage do
  @moduledoc "One bounded persisted-history page for an authorized call inspection."

  alias Vxpipe.Calls.{ArchiveStatus, CallSummary, CallTimelineEntry}

  @enforce_keys [
    :call,
    :timeline,
    :next_cursor,
    :archive_status,
    :persisted_variable_revision
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          call: CallSummary.t(),
          timeline: [CallTimelineEntry.t()],
          next_cursor: String.t() | nil,
          archive_status: ArchiveStatus.t(),
          persisted_variable_revision: non_neg_integer() | nil
        }
end
