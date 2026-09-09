defmodule Vxpipe.Calls.CallDetailPage do
  @moduledoc "One bounded persisted-history page for an authorized call inspection."

  alias Vxpipe.Calls.{CallSummary, CallTimelineEntry}

  @enforce_keys [:call, :timeline, :next_cursor]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          call: CallSummary.t(),
          timeline: [CallTimelineEntry.t()],
          next_cursor: String.t() | nil
        }
end
